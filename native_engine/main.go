package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type Command struct {
	Type     string `json:"type"` // START, PAUSE, RESUME, CANCEL
	ID       string `json:"id"`
	URL      string `json:"url,omitempty"`
	SavePath string `json:"savePath,omitempty"`
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

func handleCommand(cmd Command) {
	mu.Lock()
	defer mu.Unlock()

	switch cmd.Type {
	case "START", "RESUME":
		if state, ok := activeDownloads[cmd.ID]; ok {
			if state.Status == "downloading" {
				return
			}
			// Resume existing
			ctx, cancel := context.WithCancel(context.Background())
			state.Ctx = ctx
			state.Cancel = cancel
			state.Status = "downloading"
			go runDownload(state)
		} else if cmd.Type == "START" {
			// New download
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
	}
}

func runDownload(state *DownloadState) {
	err := os.MkdirAll(filepath.Dir(state.SavePath), 0755)
	if err != nil {
		sendUpdate(ProgressUpdate{ID: state.ID, Status: "error"})
		return
	}

	client := &http.Client{
		Transport: http.DefaultTransport,
	}

	req, err := http.NewRequestWithContext(state.Ctx, "GET", state.URL, nil)
	if err != nil {
		sendUpdate(ProgressUpdate{ID: state.ID, Status: "error"})
		return
	}

	// Range request for resuming
	if state.Downloaded > 0 {
		req.Header.Set("Range", fmt.Sprintf("bytes=%d-", state.Downloaded))
	}

	resp, err := client.Do(req)
	if err != nil {
		if state.Ctx.Err() != nil {
			return // Cancelled/Paused
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
