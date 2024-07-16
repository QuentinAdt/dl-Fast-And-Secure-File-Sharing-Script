function dl() {
    local file=""
    local port=4443
    local random_port=false
    local OPTIND

    # Parse options
    while getopts ":p:r" opt; do
        case $opt in
            p) port="$OPTARG"; random_port=false ;;
            r) random_port=true ;;
            \?) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
            :) echo "Option -$OPTARG requires an argument." >&2; return 1 ;;
        esac
    done
    shift $((OPTIND-1))

    # Get the file name
    if [ $# -eq 0 ]; then
        echo "Files in current directory:"
        ls
        echo ""
        read -p "Enter the name of the file you want to download: " file
    else
        file="$1"
    fi

    if [ -z "$file" ]; then
        echo "No file specified. Exiting."
        return 1
    fi

    if [ ! -f "$file" ]; then
        echo "File '$file' not found. Exiting."
        return 1
    fi

    ip=$(hostname -I | awk '{print $1}')
    openssl req -new -x509 -keyout server.pem -out server.pem -days 365 -nodes -subj "/CN=$ip" >/dev/null 2>&1

    if [ "$random_port" = true ]; then
        port=$(shuf -i 1024-65535 -n 1)
    fi

    while true; do
        if ! fuser "$port"/tcp >/dev/null 2>&1; then
            break
        fi
        if [ "$random_port" = true ]; then
            port=$(shuf -i 1024-65535 -n 1)
        else
            read -p "Port $port is already in use. Do you want to kill the running application? (y/n/c) " response
            case $response in
                [Yy]* ) fuser -k "$port"/tcp && echo "Application on port $port has been terminated." && break;;
                [Nn]* ) read -p "Enter a new port number: " port;;
                [Cc]* ) echo "Operation cancelled."; return;;
                * ) echo "Please answer y (yes), n (no), or c (cancel).";;
            esac
        fi
    done

    echo "https://$ip:$port/$file"
    python3 -c "
import http.server
import socketserver
import ssl
import urllib.parse
import chardet
import os

port = $port  # Get the port from bash variable

class EncodingAwareHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.path = urllib.parse.unquote(self.path)
        return http.server.SimpleHTTPRequestHandler.do_GET(self)
    def guess_type(self, path):
        ctype = super().guess_type(path)
        if ctype.startswith('text/'):
            encoding = self.detect_encoding(path)
            return f'{ctype}; charset={encoding}'
        return ctype
    def detect_encoding(self, path):
        try:
            with open(path, 'rb') as file:
                raw = file.read(10000)  # Read up to 10000 bytes
                result = chardet.detect(raw)
                return result['encoding'] or 'utf-8'
        except:
            return 'utf-8'

handler = EncodingAwareHandler
httpd = socketserver.TCPServer(('0.0.0.0', port), handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('server.pem')
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
"
}
