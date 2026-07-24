// go-queue is based on TUNA's git-fcgi admission controller at 5133fb4:
// https://github.com/tuna/docker-images/tree/master/git-fcgi
package main

import (
	goflag "flag"
	"fmt"
	"net"
	"sync/atomic"
	"time"

	flag "github.com/spf13/pflag"
	"k8s.io/klog/v2"
)

type config struct {
	portNumber   uint16
	queueSize    int
	updatePeriod time.Duration
}

func parseCLIParams() config {
	var cfg config
	var portNumber int

	logFlags := goflag.NewFlagSet("logging", goflag.ExitOnError)
	klog.InitFlags(logFlags)
	flag.IntVar(&portNumber, "port-number", 8888, "Port number to listen on")
	flag.IntVar(&cfg.queueSize, "queue-size", 100, "Maximum active jobs")
	flag.DurationVar(&cfg.updatePeriod, "update-period", time.Second, "Queue update period")
	flag.CommandLine.AddGoFlagSet(logFlags)
	flag.CommandLine.SortFlags = false
	flag.Parse()

	if portNumber < 1 || portNumber > 65535 {
		klog.Exitf("Invalid port number: %d. Must be between 1 and 65535.", portNumber)
	}
	cfg.portNumber = uint16(portNumber)
	if cfg.queueSize <= 0 {
		klog.Exitf("Invalid queue size: %d. Must be greater than 0.", cfg.queueSize)
	}
	if cfg.updatePeriod <= 0 {
		klog.Exitf("Invalid update period: %v. Must be greater than 0.", cfg.updatePeriod)
	}

	return cfg
}

var idCounter uint64

func generateID() uint64 {
	if idCounter == ^uint64(0) {
		klog.Fatal("ID counter overflow")
	}
	idCounter++
	return idCounter
}

var currentID atomic.Uint64

func getCurrentID() uint64 {
	return currentID.Load()
}

func updateCurrentID(newID uint64) {
	for {
		oldID := currentID.Load()
		if oldID >= newID {
			return
		}
		if currentID.CompareAndSwap(oldID, newID) {
			return
		}
	}
}

func serveClient(conn net.Conn, waitingQueue chan chan struct{}, reportInterval time.Duration) {
	myID := generateID()
	wakeUp := make(chan struct{})
	closed := make(chan struct{})

	go func() {
		select {
		case waitingQueue <- closed:
			close(wakeUp)
		case <-closed:
		}
	}()

	go func() {
		var readBuf [1]byte
		for {
			if _, err := conn.Read(readBuf[:]); err != nil {
				close(closed)
				_ = conn.Close()
				return
			}
		}
	}()

	go func() {
		timer := time.NewTimer(reportInterval)
		defer timer.Stop()
		for {
			select {
			case <-wakeUp:
				updateCurrentID(myID)
				_, _ = fmt.Fprintln(conn, 0)
				return
			case <-closed:
				return
			case <-timer.C:
				current := getCurrentID()
				position := uint64(1)
				if current < myID {
					position = myID - current
				}
				_, _ = fmt.Fprintln(conn, position)
				timer.Reset(reportInterval)
			}
		}
	}()
}

func listen(addr string, connections chan<- net.Conn) {
	listener, err := net.Listen("tcp4", addr)
	if err != nil {
		klog.Exitf("Failed to listen on %s: %v", addr, err)
	}
	defer listener.Close()
	for {
		conn, err := listener.Accept()
		if err != nil {
			klog.Errorf("Failed to accept connection: %v", err)
			continue
		}
		connections <- conn
	}
}

func main() {
	cfg := parseCLIParams()
	clientQueue := make(chan chan struct{})

	for range cfg.queueSize {
		go func() {
			for {
				done := <-clientQueue
				<-done
			}
		}()
	}

	connections := make(chan net.Conn)
	go listen(fmt.Sprintf("127.0.0.1:%d", cfg.portNumber), connections)

	for conn := range connections {
		serveClient(conn, clientQueue, cfg.updatePeriod)
	}
}
