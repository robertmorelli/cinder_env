package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/client"
	"github.com/docker/docker/pkg/stdcopy"
)

// injected at build time: go build -ldflags "-X main.imageName=my-image"
var imageName = "cinder-env"
var structuredMode bool

const daemonContainer = "cinder-env-daemon"

var defaultJitFlags = []string{
	"-X", "jit",
	"-X", "jit-enable-jit-list-wildcards",
	"-X", "jit-shadow-frame",
	"-X", "jit-list-file=/jitlist_main.txt",
}

type cinderConfig struct {
	Flags   []string `json:"flags"`
	JitList string   `json:"jit_list"`
}

type structuredResult struct {
	Stdout string `json:"stdout"`
	Stderr string `json:"stderr"`
	Code   int    `json:"code"`
	Error  string `json:"error,omitempty"`
}

func exitResult(stdout, stderr string, code int, errKind string) {
	if structuredMode {
		result := structuredResult{
			Stdout: stdout,
			Stderr: stderr,
			Code:   code,
		}
		if errKind != "" {
			result.Error = errKind
		}
		enc := json.NewEncoder(os.Stdout)
		enc.SetEscapeHTML(false)
		if err := enc.Encode(result); err != nil {
			fmt.Fprintf(
				os.Stdout,
				`{"stdout":%q,"stderr":%q,"code":%d,"error":"structured encode failure"}`+"\n",
				stdout,
				stderr,
				code,
			)
		}
	} else {
		if stdout != "" {
			fmt.Fprint(os.Stdout, stdout)
		}
		if stderr != "" {
			fmt.Fprint(os.Stderr, stderr)
		}
	}
	os.Exit(code)
}

func errExit(kind, msg string, code int) {
	if structuredMode {
		exitResult("", msg, code, kind)
	}
	if kind != "" {
		fmt.Fprintf(os.Stderr, "%s: %s\n", kind, msg)
	} else {
		fmt.Fprintln(os.Stderr, msg)
	}
	os.Exit(code)
}

func parseArgs(args []string) (configFile string, skipTypecheck bool, structured bool, passthrough []string) {
	for _, a := range args {
		switch {
		case strings.HasPrefix(a, "--config="):
			configFile = strings.TrimPrefix(a, "--config=")
		case a == "--skip-typecheck":
			skipTypecheck = true
		case a == "--structured":
			structured = true
		default:
			passthrough = append(passthrough, a)
		}
	}
	return
}

func typecheckPycPath(passthrough []string) string {
	if len(passthrough) == 0 {
		return ""
	}
	input := passthrough[0]
	if strings.HasPrefix(input, "-") || input == "" {
		return ""
	}
	if dot := strings.LastIndex(input, "."); dot != -1 {
		return input[:dot] + ".pyc"
	}
	return input + ".pyc"
}

func resolveJitFlags(configFile string) []string {
	if configFile == "" {
		return defaultJitFlags
	}
	f, err := os.Open(configFile)
	if err != nil {
		errExit("docker error", "cannot open config: "+err.Error(), 1)
	}
	defer f.Close()

	var cfg cinderConfig
	if err := json.NewDecoder(f).Decode(&cfg); err != nil {
		errExit("docker error", "invalid config JSON: "+err.Error(), 1)
	}
	flags := cfg.Flags
	if len(flags) == 0 {
		flags = append([]string(nil), defaultJitFlags...)
	}
	jitList := cfg.JitList
	if jitList == "" {
		jitList = "/jitlist_main.txt"
	}
	return append(flags, "-X", "jit-list-file="+jitList)
}

func dockerHost() client.Opt {
	if host := os.Getenv("DOCKER_HOST"); host != "" {
		return client.WithHost(host)
	}
	if runtime.GOOS == "darwin" {
		macSocket := filepath.Join(os.Getenv("HOME"), ".docker/run/docker.sock")
		if _, err := os.Stat(macSocket); err == nil {
			return client.WithHost("unix://" + macSocket)
		}
	}
	return client.WithHost(client.DefaultDockerHost)
}

func isRunningWithMount(ctx context.Context, cli *client.Client, cwd string) bool {
	info, err := cli.ContainerInspect(ctx, daemonContainer)
	if err != nil || !info.State.Running {
		return false
	}
	for _, m := range info.Mounts {
		if m.Source == cwd {
			return true
		}
	}
	return false
}

func ensureContainer(ctx context.Context, cli *client.Client, cwd string) {
	if isRunningWithMount(ctx, cli, cwd) {
		return
	}
	cli.ContainerRemove(ctx, daemonContainer, container.RemoveOptions{Force: true}) //nolint
	resp, err := cli.ContainerCreate(ctx,
		&container.Config{
			Image:      imageName,
			Entrypoint: []string{"sleep"},
			Cmd:        []string{"infinity"},
			WorkingDir: "/app",
		},
		&container.HostConfig{
			Binds: []string{cwd + ":/app"},
		},
		nil, nil, daemonContainer,
	)
	if err != nil {
		errExit("docker error", "container create: "+err.Error(), 1)
	}
	if err := cli.ContainerStart(ctx, resp.ID, container.StartOptions{}); err != nil {
		errExit("docker error", "container start: "+err.Error(), 1)
	}
}

func execCapture(ctx context.Context, cli *client.Client, cmd []string) (stdout, stderr string, exitCode int) {
	exec, err := cli.ContainerExecCreate(ctx, daemonContainer, container.ExecOptions{
		Cmd:          cmd,
		AttachStdout: true,
		AttachStderr: true,
		WorkingDir:   "/app",
	})
	if err != nil {
		errExit("docker error", "exec create: "+err.Error(), 1)
	}
	resp, err := cli.ContainerExecAttach(ctx, exec.ID, container.ExecAttachOptions{})
	if err != nil {
		errExit("docker error", "exec attach: "+err.Error(), 1)
	}
	defer resp.Close()

	var outBuf, errBuf bytes.Buffer
	if _, err := stdcopy.StdCopy(&outBuf, &errBuf, resp.Reader); err != nil {
		errExit("docker error", "read output: "+err.Error(), 1)
	}
	info, err := cli.ContainerExecInspect(ctx, exec.ID)
	if err != nil {
		errExit("docker error", "exec inspect: "+err.Error(), 1)
	}
	return outBuf.String(), errBuf.String(), info.ExitCode
}

func main() {
	ctx := context.Background()

	configFile, skipTypecheck, structured, passthrough := parseArgs(os.Args[1:])
	structuredMode = structured
	jitFlags := resolveJitFlags(configFile)

	cli, err := client.NewClientWithOpts(dockerHost(), client.WithAPIVersionNegotiation())
	if err != nil {
		errExit("docker error", "cannot connect to Docker: "+err.Error(), 1)
	}
	defer cli.Close()

	cwd, _ := os.Getwd()
	ensureContainer(ctx, cli, cwd)

	execCapture(ctx, cli, []string{"/bin/bash", "-c", "rm -rf /scratch && mkdir /scratch"})

	if !skipTypecheck {
		tcCmd := append([]string{"python", "-m", "cinderx.compiler", "--static", "-c"}, passthrough...)
		tcOut, tcErr, tcCode := execCapture(ctx, cli, tcCmd)
		if tcCode != 0 {
			exitResult(tcOut, tcErr, tcCode, "typecheck error")
		}
		if pycPath := typecheckPycPath(passthrough); pycPath != "" {
			execCapture(ctx, cli, []string{
				"python",
				"-c",
				"import os,sys; p=sys.argv[1];\ntry:\n os.remove(p)\nexcept FileNotFoundError:\n pass",
				pycPath,
			})
		}
	}

	runCmd := append(append([]string{"python"}, jitFlags...), passthrough...)
	runOut, runErr, exitCode := execCapture(ctx, cli, runCmd)
	errKind := ""
	if exitCode != 0 {
		errKind = "runtime error"
	}
	exitResult(runOut, runErr, exitCode, errKind)
}
