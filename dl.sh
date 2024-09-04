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
        read -p "Enter the name of the file you want to share: " file
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

    # Check if Python 3 is installed
    if ! command -v python3 &> /dev/null; then
        echo "Python 3 is not installed. Please install it to use this function."
        return 1
    fi

    # Check if the chardet module is installed
    if ! python3 -c "import chardet" &> /dev/null; then
        echo "The Python 'chardet' module is not installed. Installing..."
        if ! pip3 install chardet; then
            echo "Unable to install chardet. Please install it manually."
            return 1
        fi
    fi

    ip=$(hostname -I | awk '{print $1}')
    if [ -z "$ip" ]; then
        echo "Unable to obtain IP address. Exiting."
        return 1
    fi

    if ! openssl req -new -x509 -keyout server.pem -out server.pem -days 365 -nodes -subj "/CN=$ip" >/dev/null 2>&1; then
        echo "Error creating SSL certificate. Exiting."
        return 1
    fi

    # Function to check if a port is open
    check_port_open() {
        local port=$1
        if nc -z localhost $port &>/dev/null; then
            return 0  # Port is open
        else
            return 1  # Port is closed
        fi
    }

    # Function to temporarily open a port
    open_port_temporarily() {
        local port=$1
        if command -v ufw &> /dev/null; then
            sudo ufw allow $port/tcp
        elif command -v firewall-cmd &> /dev/null; then
            sudo firewall-cmd --add-port=$port/tcp --temporary
        elif command -v iptables &> /dev/null; then
            sudo iptables -A INPUT -p tcp --dport $port -j ACCEPT
        else
            echo "No recognized firewall found. Unable to open port automatically."
            return 1
        fi
        echo "Port $port temporarily opened."
    }

    if [ "$random_port" = true ]; then
        port=$(shuf -i 1024-65535 -n 1)
    fi

    # Check if the port is open and free
    while true; do
        if ! fuser "$port"/tcp >/dev/null 2>&1; then
            if check_port_open $port; then
                break
            else
                read -p "Port $port is closed. Do you want to open it temporarily? (y/n) " response
                case $response in
                    [Yy]* ) 
                        if open_port_temporarily $port; then
                            break
                        else
                            read -p "Failed to open port. Do you want to try another port? (y/n) " retry
                            case $retry in
                                [Yy]* ) read -p "Enter a new port number: " port ;;
                                * ) echo "Operation canceled."; return 1 ;;
                            esac
                        fi
                        ;;
                    * ) 
                        read -p "Do you want to try another port? (y/n) " retry
                        case $retry in
                            [Yy]* ) read -p "Enter a new port number: " port ;;
                            * ) echo "Operation canceled."; return 1 ;;
                        esac
                        ;;
                esac
            fi
        else
            read -p "Port $port is already in use. Do you want to try another port? (y/n/k) " response
            case $response in
                [Yy]* ) read -p "Enter a new port number: " port ;;
                [Kk]* ) 
                    if ! fuser -k "$port"/tcp; then
                        echo "Unable to free port $port. Exiting."
                        return 1
                    fi
                    break
                    ;;
                * ) echo "Operation canceled."; return 1 ;;
            esac
        fi
    done

    echo "The file '$file' is available at the following address:"
    echo "https://$ip:$port/$file"
    echo "To download the file while ignoring the SSL warning, use the following command:"
    echo "curl -k -O https://$ip:$port/$file"
    echo "Warning: The -k option disables SSL verification. Use it only in a trusted environment."
    
    echo "To use wget while ignoring the SSL warning:"
    echo "wget --no-check-certificate https://$ip:$port/$file"
    
    echo "For a secure connection, you can first download the certificate:"
    echo "curl -k -O https://$ip:$port/server.pem"
    echo "Then use it for subsequent downloads:"
    echo "curl --cacert server.pem -O https://$ip:$port/$file"

    python3 -c "
import http.server
import socketserver
import ssl
import urllib.parse
import chardet
import os

port = $port  # Get the port from bash variable
shared_file = '$file'  # Get the name of the shared file

class SecureHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/server.pem':
            self.send_response(200)
            self.send_header('Content-type', 'application/x-pem-file')
            self.send_header('Content-Disposition', 'attachment; filename=\"server.pem\"')
            self.end_headers()
            with open('server.pem', 'rb') as file:
                self.wfile.write(file.read())
            return
        elif self.path == '/' or self.path == '':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            message = f'''
            <html>
            <head><title>Shared File</title></head>
            <body>
            <h1>Shared File</h1>
            <p>The shared file is: <a href=\"/{shared_file}\">{shared_file}</a></p>
            </body>
            </html>
            '''
            self.wfile.write(message.encode())
            return
        elif self.path == f'/{shared_file}':
            return http.server.SimpleHTTPRequestHandler.do_GET(self)
        else:
            self.send_error(404, 'File not found')
            return

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

handler = SecureHandler
httpd = socketserver.TCPServer(('0.0.0.0', port), handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('server.pem')
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
print(f'Server started on https://{os.uname()[1]}:{port}')
httpd.serve_forever()
"
}
