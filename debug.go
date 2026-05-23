package main

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"strings"
)

func runAPIDebug(args []string) error {
	client := NewUniCsACClient(DefaultBaseURL)
	route := "test"
	if len(args) > 0 && strings.TrimSpace(args[0]) != "" {
		route = strings.TrimSpace(args[0])
	}

	var out APIResponse
	if route == "auth/login" {
		username := os.Getenv("CSAC_USERNAME")
		password := os.Getenv("CSAC_PASSWORD")
		if username == "" || password == "" {
			return fmt.Errorf("set CSAC_USERNAME and CSAC_PASSWORD to debug auth/login")
		}
		err := client.PostForm(route, url.Values{"username": {username}, "pwd": {password}}, &out)
		printDebugResponse(route, out, err)
		return err
	}

	err := client.Get(route, nil, &out)
	printDebugResponse(route, out, err)
	return err
}

func printDebugResponse(route string, out APIResponse, err error) {
	fmt.Println("route:", route)
	if err != nil {
		fmt.Println("error:", err)
	}
	body, marshalErr := json.MarshalIndent(out.Raw, "", "  ")
	if marshalErr == nil && len(out.Raw) > 0 {
		fmt.Println(string(body))
		return
	}
	body, marshalErr = json.MarshalIndent(out, "", "  ")
	if marshalErr == nil {
		fmt.Println(string(body))
	}
}
