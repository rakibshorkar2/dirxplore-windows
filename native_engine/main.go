package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type Command struct {
	Type     string `json:"type"` // START, PAUSE, RESUME, CANCEL, TEST
	ID       string `json:"id"`
	URL      string `json:"url,omitempty"`
	SavePath string `json:"savePath,omitempty"`
	ProxyURL string `json:"proxyUrl,omitempty"`
}

type ProgressUpdate struct {
	ID         string  `json:"id"`
	Downloaded int64   `json:"downloaded"`
	Total      int64   `json:"total"`
	Progress   float64 `json:"progress"`
	Speed      int64   `json:"speed"`
	Status     string  `json:"status"`
}

type DownloadState struct {
	ID         string
	URL        string
	SavePath   string
	Downloaded int64
	Total      int64
	Status     string
	Cancel     context.CancelFunc
	Ctx        context.Context
}

var (
	activeDownloads = make(map[string]*DownloadState)
	mu              sync.Mutex
)

func main() {
	// Start local proxy gateway
	go startProxyGateway()

	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		var cmd Command
		err := json.Unmarshal(scanner.Bytes(), &cmd)
		if err != nil {
			sendError("Invalid command: " + err.Error())
			continue
		}

		handleCommand(cmd)
	}
}

func startProxyGateway() {
	handler := &ProxyHandler{}
	server := &http.Server{
		Handler: handler,
	}

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		sendError("Failed to start proxy listener: " + err.Error())
		return
	}

	fmt.Printf("LOCAL_PROXY_PORT:%d\n", listener.Addr().(*net.TCPAddr).Port)

	if err := server.Serve(listener); err != nil {
		sendError("Proxy server error: " + err.Error())
	}
}

type ProxyHandler struct{}

func (h *ProxyHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodConnect {
		h.handleConnect(w, r)
		return
	}

	// Normal HTTP request
	resp, err := http.DefaultTransport.RoundTrip(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}
	defer resp.Body.Close()

	copyHeader(w.Header(), resp.Header)
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func (h *ProxyHandler) handleConnect(w http.ResponseWriter, r *http.Request) {
	destConn, err := net.DialTimeout("tcp", r.Host, 10*time.Second)
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)

	hijacker, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "Hijacking not supported", http.StatusInternalServerError)
		return
	}

	clientConn, _, err := hijacker.Hijack()
	if err != nil {
		destConn.Close()
		return
	}

	go tunnel(clientConn, destConn)
	go tunnel(destConn, clientConn)
}

func tunnel(src, dst net.Conn) {
	defer src.Close()
	defer dst.Close()
	io.Copy(dst, src)
}

func copyHeader(dst, src http.Header) {
	for k, vv := range src {
		for _, v := range vv {
			dst.Add(k, v)
		}
	}
}

func handleCommand(cmd Command) {
	mu.Lock()
	defer mu.Unlock()

	switch cmd.Type {
	case "START", "RESUME":
		if state, ok := activeDownloads[cmd.ID]; ok {
			if state.Status == "downloading" {
				return
			}
			ctx, cancel := context.WithCancel(context.Background())
			state.Ctx = ctx
			state.Cancel = cancel
			state.Status = "downloading"
			go runDownload(state)
		} else if cmd.Type == "START" {
			ctx, cancel := context.WithCancel(context.Background())
			state := &DownloadState{
				ID:       cmd.ID,
				URL:      cmd.URL,
				SavePath: cmd.SavePath,
				Status:   "downloading",
				Ctx:      ctx,
				Cancel:   cancel,
			}
			activeDownloads[cmd.ID] = state
			go runDownload(state)
		}
	case "PAUSE":
		if state, ok := activeDownloads[cmd.ID]; ok {
			if state.Cancel != nil {
				state.Cancel()
			}
			state.Status = "paused"
			sendUpdate(ProgressUpdate{ID: state.ID, Status: "paused", Downloaded: state.Downloaded, Total: state.Total})
		}
	case "CANCEL":
		if state, ok := activeDownloads[cmd.ID]; ok {
			if state.Cancel != nil {
				state.Cancel()
			}
			delete(activeDownloads, cmd.ID)
		}
	case "TEST":
		go performTest(cmd)
	}
}

func performTest(cmd Command) {
	client := http.DefaultClient
	if cmd.ProxyURL != "" {
		pURL, err := url.Parse(cmd.ProxyURL)
		if err == nil {
			client = &http.Client{
				Transport: &http.Transport{
					Proxy: http.ProxyURL(pURL),
				},
				Timeout: 15 * time.Second,
			}
		}
	}

	start := time.Now()
	resp, err := client.Get(cmd.URL)
	latency := time.Since(start).Milliseconds()

	result := map[string]interface{}{
		"type":    "TEST_RESULT",
		"id":      cmd.ID,
		"url":     cmd.URL,
		"latency": latency,
		"success": err == nil,
	}
	if err != nil {
		result["error"] = err.Error()
	} else {
		result["status"] = resp.StatusCode
		resp.Body.Close()
	}

	data, _ := json.Marshal(result)
	fmt.Println(string(data))
}

func runDownload(state *DownloadState) {
	err := os.MkdirAll(filepath.Dir(state.SavePath), 0755)
	if err != nil {
		sendUpdate(ProgressUpdate{ID: state.ID, Status: "error"})
		return
	}

	req, err := http.NewRequestWithContext(state.Ctx, "GET", state.URL, nil)
	if err != nil {
		sendUpdate(ProgressUpdate{ID: state.ID, Status: "error"})
		return
	}

	if state.Downloaded > 0 {
		req.Header.Set("Range", fmt.Sprintf("bytes=%d-", state.Downloaded))
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		if state.Ctx.Err() != nil {
			return
		}
		sendUpdate(ProgressUpdate{ID: state.ID, Status: "error"})
		return
	}
	defer resp.Body.Close()

	if state.Downloaded == 0 {
		state.Total = resp.ContentLength
	} else if resp.StatusCode != http.StatusPartialContent && resp.StatusCode != http.StatusOK {
		sendUpdate(ProgressUpdate{ID: state.ID, Status: "error"})
		return
	}

	var file *os.File
	if state.Downloaded == 0 {
		file, err = os.Create(state.SavePath)
	} else {
		file, err = os.OpenFile(state.SavePath, os.O_APPEND|os.O_WRONLY, 0644)
	}

	if err != nil {
		sendUpdate(ProgressUpdate{ID: state.ID, Status: "error"})
		return
	}
	defer file.Close()

	buffer := make([]byte, 64*1024)
	lastUpdate := time.Now()
	lastDownloaded := state.Downloaded

	for {
		select {
		case <-state.Ctx.Done():
			return
		default:
			n, err := resp.Body.Read(buffer)
			if n > 0 {
				_, writeErr := file.Write(buffer[:n])
				if writeErr != nil {
					sendUpdate(ProgressUpdate{ID: state.ID, Status: "error"})
					return
				}
				state.Downloaded += int64(n)

				if time.Since(lastUpdate) > 500*time.Millisecond {
					speed := int64(float64(state.Downloaded-lastDownloaded) / time.Since(lastUpdate).Seconds())
					progress := 0.0
					if state.Total > 0 {
						progress = float64(state.Downloaded) / float64(state.Total)
					}
					sendUpdate(ProgressUpdate{
						ID:         state.ID,
						Downloaded: state.Downloaded,
						Total:      state.Total,
						Progress:   progress,
						Speed:      speed,
						Status:     "downloading",
					})
					lastUpdate = time.Now()
					lastDownloaded = state.Downloaded
				}
			}
			if err == io.EOF {
				sendUpdate(ProgressUpdate{
					ID:         state.ID,
					Downloaded: state.Downloaded,
					Total:      state.Total,
					Progress:   1.0,
					Status:     "completed",
				})
				mu.Lock()
				delete(activeDownloads, state.ID)
				mu.Unlock()
				return
			}
			if err != nil {
				if state.Ctx.Err() != nil {
					return
				}
				sendUpdate(ProgressUpdate{ID: state.ID, Status: "error"})
				return
			}
		}
	}
}

func sendUpdate(update ProgressUpdate) {
	data, _ := json.Marshal(update)
	fmt.Println(string(data))
}

func sendError(message string) {
	fmt.Fprintf(os.Stderr, "Error: %s\n", message)
}
