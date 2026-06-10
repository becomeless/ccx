package tui

import (
	"bytes"
	"testing"
)

func TestDropStaleFirstLineFeed(t *testing.T) {
	cases := []struct {
		name string
		in   []byte
		want []byte
	}{
		{"empty", []byte{}, []byte{}},
		{"lone-lf", []byte{'\n'}, []byte{}},
		{"lf-before-typed-value", []byte("\nmimo-v2.5[1m]"), []byte("mimo-v2.5[1m]")},
		{"cr-enter-untouched", []byte{'\r'}, []byte{'\r'}},
		{"esc-untouched", []byte{0x1b}, []byte{0x1b}},
		{"ordinary-value-untouched", []byte("mimo-v2.5[1m]"), []byte("mimo-v2.5[1m]")},
	}

	for _, c := range cases {
		got := dropStaleFirstLineFeed(c.in)
		if !bytes.Equal(got, c.want) {
			t.Fatalf("%s: got %q want %q", c.name, got, c.want)
		}
	}
}
