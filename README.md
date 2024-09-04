# File Sharing Script

This repository contains a Bash function `dl()` that allows easy and secure file sharing over a local network using HTTPS.

## Features

- Shares a single file over HTTPS
- Creates a self-signed SSL certificate
- Supports custom port selection or random port assignment
- Provides secure download instructions

## Requirements

- Bash
- Python 3
- OpenSSL
- netcat (nc)

## Installation

1. Clone this repository:
   ```
   git clone https://github.com/yourusername/file-sharing-script.git
   ```

2. Add the following line to your `.bashrc` or `.zshrc`:
   ```
   source /path/to/file-sharing-script/dl.sh
   ```

3. Reload your shell configuration:
   ```
   source ~/.bashrc
   ```
   or
   ```
   source ~/.zshrc
   ```

## Usage

To share a file:

```
dl /path/to/your/file
```

Options:
- `-p <port>`: Specify a custom port
- `-r`: Use a random port

Follow the on-screen instructions to download the file securely.

## Security Note

This script uses a self-signed SSL certificate. While this encrypts the connection, it does not provide authentication. Use this script only in trusted environments.

## License

[MIT License](LICENSE)
