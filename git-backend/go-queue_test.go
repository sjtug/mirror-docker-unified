package main

import (
	"bufio"
	"net"
	"testing"
	"time"
)

func startTestWorkers(count int, queue chan chan struct{}) {
	for range count {
		go func() {
			for {
				done := <-queue
				<-done
			}
		}()
	}
}

func newTestClient(t *testing.T, queue chan chan struct{}) net.Conn {
	t.Helper()
	server, client := net.Pipe()
	serveClient(server, queue, time.Hour)
	t.Cleanup(func() { _ = client.Close() })
	return client
}

func readGrant(t *testing.T, conn net.Conn, timeout time.Duration) string {
	t.Helper()
	if err := conn.SetReadDeadline(time.Now().Add(timeout)); err != nil {
		t.Fatal(err)
	}
	line, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil {
		t.Fatalf("read grant: %v", err)
	}
	if err := conn.SetReadDeadline(time.Time{}); err != nil {
		t.Fatal(err)
	}
	return line
}

func expectNoGrant(t *testing.T, conn net.Conn, timeout time.Duration) {
	t.Helper()
	if err := conn.SetReadDeadline(time.Now().Add(timeout)); err != nil {
		t.Fatal(err)
	}
	var b [1]byte
	_, err := conn.Read(b[:])
	if err == nil {
		t.Fatal("received a grant while all slots were active")
	}
	if timeoutErr, ok := err.(net.Error); !ok || !timeoutErr.Timeout() {
		t.Fatalf("expected read timeout, got %v", err)
	}
	if err := conn.SetReadDeadline(time.Time{}); err != nil {
		t.Fatal(err)
	}
}

func resetTestIDs() {
	idCounter = 0
	currentID.Store(0)
}

func TestAdmissionLimitAndRelease(t *testing.T) {
	resetTestIDs()
	queue := make(chan chan struct{})
	startTestWorkers(1, queue)

	first := newTestClient(t, queue)
	if got := readGrant(t, first, time.Second); got != "0\n" {
		t.Fatalf("first grant = %q, want %q", got, "0\n")
	}

	second := newTestClient(t, queue)
	expectNoGrant(t, second, 100*time.Millisecond)
	if err := first.Close(); err != nil {
		t.Fatal(err)
	}
	if got := readGrant(t, second, time.Second); got != "0\n" {
		t.Fatalf("second grant = %q, want %q", got, "0\n")
	}
}

func TestCanceledWaiterDoesNotConsumeSlot(t *testing.T) {
	resetTestIDs()
	queue := make(chan chan struct{})
	startTestWorkers(1, queue)

	active := newTestClient(t, queue)
	if got := readGrant(t, active, time.Second); got != "0\n" {
		t.Fatalf("active grant = %q, want %q", got, "0\n")
	}

	canceled := newTestClient(t, queue)
	expectNoGrant(t, canceled, 100*time.Millisecond)
	if err := canceled.Close(); err != nil {
		t.Fatal(err)
	}

	next := newTestClient(t, queue)
	expectNoGrant(t, next, 100*time.Millisecond)
	if err := active.Close(); err != nil {
		t.Fatal(err)
	}
	if got := readGrant(t, next, time.Second); got != "0\n" {
		t.Fatalf("next grant = %q, want %q", got, "0\n")
	}
}
