package task

import (
	"os"
	"testing"
	"time"

	"github.com/circleci/ex/config/secret"
	"github.com/circleci/ex/testing/testcontext"
	"github.com/google/go-cmp/cmp/cmpopts"
	"gotest.tools/v3/assert"
	"gotest.tools/v3/assert/cmp"
)

func Test_ReadFromStdin(t *testing.T) {
	ctx := testcontext.Background()

	goodConfig := `
{
	"entrypoint": [],
	"token": "testtoken",
	"task_agent_path": "/path/to/agent",
	"runner_api_base_url": "https://example.com/api",
	"allocation": "testallocation",
	"ssh_advertise_addr": "192.168.1.1",
	"max_run_time": 60000000000,
	"token_checksum": "ada63e98fe50eccb55036d88eda4b2c3709f53c2b65bc0335797067e9a2a5d8b"
}`
	goodTimeout := configReadTimeout

	tests := []struct {
		name string

		rawConfig string
		timeout   time.Duration

		wantConfig Config
		wantError  string
	}{
		{
			name:      "valid",
			rawConfig: goodConfig,
			timeout:   goodTimeout,
			wantConfig: Config{
				Entrypoint:       []string{},
				Token:            secret.String("testtoken"),
				TaskAgentPath:    "/path/to/agent",
				RunnerAPIBaseURL: "https://example.com/api",
				Allocation:       "testallocation",
				SSHAdvertiseAddr: "192.168.1.1",
				MaxRunTime:       time.Duration(60000000000),
			},
		},
		{
			name:      "invalid",
			rawConfig: `not a valid JSON string`,
			timeout:   goodTimeout,
			wantError: "failed to unmarshal config",
		},
		{
			name:      "invalid checksum",
			timeout:   goodTimeout,
			rawConfig: `{"token": "tasktoken","token_checksum": "invalid"}`,
			wantError: "invalid checksum on config token",
		},
		{
			name:      "timeout",
			rawConfig: goodConfig,
			timeout:   1 * time.Nanosecond,
			wantError: "timed out reading config from stdin",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			configReadTimeout = tt.timeout

			config := Config{}

			// Simulate Stdin
			r, w, _ := os.Pipe()
			os.Stdin = r
			_, err := w.Write([]byte(tt.rawConfig))
			assert.NilError(t, err)
			err = w.Close()
			assert.NilError(t, err)

			err = config.ReadFromStdin(ctx)
			if tt.wantError == "" {
				assert.NilError(t, err)
				assert.Check(t, cmp.DeepEqual(config, tt.wantConfig, cmpopts.IgnoreFields(Config{}, "TokenChecksum")))
			} else {
				assert.Check(t, cmp.ErrorContains(err, tt.wantError))
			}
		})
	}
}

func Test_TaskAgentCmd(t *testing.T) {
	config := &Config{
		TaskAgentPath:    "/path/to/agent",
		RunnerAPIBaseURL: "https://example.com/api",
		Allocation:       "testallocation",
		MaxRunTime:       60 * time.Minute,
		SSHAdvertiseAddr: "192.168.1.1",
	}

	expectedCmd := "PATH=$PATH:/path/to /path/to/agent _internal " +
		"agent-runner --verbose --runnerAPIBaseURL=https://example.com/api " +
		"--allocation=testallocation --disableSpinUpStep --disableIsolatedSSHDir " +
		"--maxRunTime=3600 --sshAdvertiseAddr=192.168.1.1"

	assert.Check(t, cmp.Equal(config.TaskAgentCmd(), expectedCmd))
}
