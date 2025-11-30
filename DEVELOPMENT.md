# Development Guide

## Running Tests

Tests use [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System):

```bash
# Install BATS (if not already installed)
git clone https://github.com/bats-core/bats-core.git
sudo ./bats-core/install.sh /usr/local

# Run all tests
bats tests/

# Run specific test file
bats tests/01-foundation.bats

# Run with verbose output
bats -t tests/
```

## Development Dependencies

```bash
# Debian/Ubuntu
sudo apt-get install shellcheck dash

# Validate POSIX compliance
shellcheck -s sh bench
dash -n bench
```

## Recording Demo

The demo video is created using [asciinema](https://asciinema.org/) and converted to MP4.

### Prerequisites

```bash
# Install asciinema
sudo apt-get install asciinema

# Install agg (asciinema gif generator)
# Download from https://github.com/asciinema/agg/releases
wget https://github.com/asciinema/agg/releases/download/v1.7.0/agg-x86_64-unknown-linux-gnu
chmod +x agg-x86_64-unknown-linux-gnu
sudo mv agg-x86_64-unknown-linux-gnu /usr/local/bin/agg

# Install ffmpeg for MP4 conversion
sudo apt-get install ffmpeg
```

### Recording

```bash
# Record terminal session
asciinema rec demo.cast

# Preview recording
asciinema play demo.cast
```

### Editing Cast Files

Cast files are newline-delimited JSON. First line is header, subsequent lines are events:

```json
{"version": 2, "width": 120, "height": 40, "timestamp": 1234567890, "idle_time_limit": 2}
[0.5, "o", "$ bench --runs 5 \"echo test\"\r\n"]
[1.2, "o", "Running benchmark...\r\n"]
```

Edit timestamps and content directly, or use Python for bulk edits:

```python
import json

with open('demo.cast', 'r') as f:
    lines = f.readlines()

# Process lines...
# lines[0] is header, lines[1:] are events [timestamp, type, data]

with open('demo-edited.cast', 'w') as f:
    f.writelines(lines)
```

### Converting to GIF and MP4

```bash
# Convert cast to GIF
agg demo.cast demo.gif

# Convert GIF to MP4
ffmpeg -i demo.gif -movflags faststart -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" demo.mp4
```

### Tips

- Set `idle_time_limit` in header to compress long pauses
- Use smaller terminal dimensions for smaller file sizes
- Preview with `asciinema play` before converting
