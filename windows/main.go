// Build with a copy of the Vite production dist directory beside this file.
package main

import (
	"embed"
	"fmt"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"time"
)

//go:embed all:dist
var assets embed.FS

func main() {
	const address = "127.0.0.1:48763"
	listener, err := net.Listen("tcp4", address)
	if err != nil {
		fmt.Println("Could not start PDF Nano. Close any existing PDF Nano window and try again.", err)
		fmt.Println("Press Enter to close.")
		fmt.Scanln()
		return
	}
	root, err := fs.Sub(assets, "dist")
	if err != nil {
		log.Fatal(err)
	}
	url := "http://" + address + "/"
	fmt.Println("PDF Nano is running at", url)
	fmt.Println("Keep this window open while reading. Close it to quit.")
	if err := exec.Command("rundll32.exe", "url.dll,FileProtocolHandler", url).Start(); err != nil {
		fmt.Fprintln(os.Stderr, "Open the address above in your browser.")
	}
	files := http.FileServer(http.FS(root))
	server := http.Server{ReadHeaderTimeout: 5 * time.Second, Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Host != address {
			http.Error(w, "Invalid host", http.StatusForbidden)
			return
		}
		files.ServeHTTP(w, r)
	})}
	log.Fatal(server.Serve(listener))
}
