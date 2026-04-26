# Seestar/ASIAIR jailbreak by @joshumax
# Licensed in the public domain
# Network scanning and multi-port support added

import socket
import os
import hashlib
import sys
import concurrent.futures

JAILBREAK_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'jailbreak.tar.bz2')

ASIAIR_PORTS = [22, 139, 445, 4030, 4040, 4350, 4360, 4400, 4500, 4700, 4800, 4801, 8888]

SIGNATURE_PORTS = [4350, 4030, 4400]

OTA_COMMAND_PORT = 4350
OTA_FILE_PORTS = [4361, 4360]


def recv_all(sock):
    text = ''

    while True:
        chunk = sock.recv(1024)
        text += chunk.decode()

        if not chunk or chunk.decode().endswith('\n'):
            break

    return text


def get_hostname(ip):
    try:
        return socket.gethostbyaddr(ip)[0]
    except (socket.herror, socket.gaierror, OSError):
        return None


def get_ssh_banner(ip, timeout=2):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect((ip, 22))
        banner = s.recv(256).decode('utf-8', errors='ignore').strip()
        s.close()
        return banner
    except (socket.timeout, OSError):
        return None


def get_ota_banner(ip, port=4350, timeout=2):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect((ip, port))
        banner = s.recv(1024).decode('utf-8', errors='ignore').strip()
        s.close()
        return banner
    except (socket.timeout, OSError):
        return None


def identify_device(ip, open_ports):
    info = {'ip': ip, 'is_asiair': False, 'confidence': 'none', 'details': []}

    hostname = get_hostname(ip)
    if hostname:
        info['hostname'] = hostname
        info['details'].append(f'Hostname: {hostname}')
        if 'asiair' in hostname.lower() or 'zwo' in hostname.lower():
            info['is_asiair'] = True
            info['confidence'] = 'high'
            info['details'].append('Hostname matches ASIAIR/ZWO pattern')

    if 22 in open_ports:
        ssh_banner = get_ssh_banner(ip)
        if ssh_banner:
            info['ssh_banner'] = ssh_banner
            info['details'].append(f'SSH banner: {ssh_banner}')

    if 4350 in open_ports:
        ota_banner = get_ota_banner(ip)
        if ota_banner:
            info['ota_banner'] = ota_banner
            info['details'].append(f'OTA service response: {ota_banner}')

    asiair_unique = [4030, 4040, 4350, 4360, 4400, 4500, 4700, 4800]
    matched = sum(1 for p in asiair_unique if p in open_ports)

    if matched >= 5:
        info['is_asiair'] = True
        info['confidence'] = 'high'
        info['details'].append(f'Port fingerprint: {matched}/{len(asiair_unique)} ASIAIR-specific ports open')
    elif matched >= 3:
        info['is_asiair'] = True
        if info['confidence'] != 'high':
            info['confidence'] = 'medium'
        info['details'].append(f'Port fingerprint: {matched}/{len(asiair_unique)} ASIAIR-specific ports open')
    elif matched >= 1:
        if info['confidence'] == 'none':
            info['confidence'] = 'low'
        info['details'].append(f'Port fingerprint: {matched}/{len(asiair_unique)} ASIAIR-specific ports open')

    return info


def check_port(ip, port, timeout=0.5):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        result = s.connect_ex((ip, port))
        s.close()
        return result == 0
    except (socket.timeout, OSError):
        return False


def get_local_subnets():
    subnets = []
    try:
        import netifaces
        for iface in netifaces.interfaces():
            addrs = netifaces.ifaddresses(iface)
            if netifaces.AF_INET in addrs:
                for addr_info in addrs[netifaces.AF_INET]:
                    ip = addr_info.get('addr', '')
                    netmask = addr_info.get('netmask', '')
                    if ip and not ip.startswith('127.'):
                        subnets.append((ip, netmask))
    except ImportError:
        pass

    if not subnets:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(('8.8.8.8', 80))
            local_ip = s.getsockname()[0]
            s.close()
            subnets.append((local_ip, '255.255.255.0'))
        except OSError:
            pass

    return subnets


def ip_range_from_subnet(ip, netmask='255.255.255.0'):
    ip_parts = [int(p) for p in ip.split('.')]
    mask_parts = [int(p) for p in netmask.split('.')]

    network = [ip_parts[i] & mask_parts[i] for i in range(4)]

    hosts = []
    host_bits = sum(bin(255 - m).count('1') for m in mask_parts)
    num_hosts = min(2 ** host_bits - 2, 254)

    for i in range(1, num_hosts + 1):
        host_ip = list(network)
        host_ip[3] = network[3] + i
        if host_ip[3] > 254:
            continue
        hosts.append('.'.join(str(p) for p in host_ip))

    return hosts


def scan_host(ip):
    if not check_port(ip, SIGNATURE_PORTS[0], timeout=0.3):
        return None

    open_ports = []
    for port in ASIAIR_PORTS:
        if check_port(ip, port, timeout=0.5):
            open_ports.append(port)

    matching = sum(1 for p in SIGNATURE_PORTS if p in open_ports)
    if matching >= 2:
        has_4801 = 4801 in open_ports
        firmware_hint = '10.74+' if has_4801 else '4.35 (or older)'
        device_info = identify_device(ip, open_ports)
        return (ip, open_ports, firmware_hint, device_info)

    return None


def scan_network():
    print('Scanning local network for ASIAIR devices...')
    subnets = get_local_subnets()

    if not subnets:
        print('Could not determine local network. Please specify IP manually.')
        return []

    found_devices = []

    for local_ip, netmask in subnets:
        print(f'Scanning subnet {local_ip}/{netmask} ...')
        hosts = ip_range_from_subnet(local_ip, netmask)

        with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
            futures = {executor.submit(scan_host, ip): ip for ip in hosts}
            for future in concurrent.futures.as_completed(futures):
                result = future.result()
                if result:
                    found_devices.append(result)
                    ip, ports, fw, info = result
                    hostname_str = f' ({info["hostname"]})' if 'hostname' in info else ''
                    conf = info['confidence']
                    print(f'  Found device: {ip}{hostname_str}')
                    print(f'    Identified as ASIAIR: {"YES" if info["is_asiair"] else "UNKNOWN"} (confidence: {conf})')
                    print(f'    Estimated firmware: {fw}')
                    print(f'    Open ports: {", ".join(str(p) for p in ports)}')
                    for detail in info['details']:
                        print(f'    {detail}')

    return found_devices


def begin_update(address, file):
    file_contents = open(file,'rb').read()
    json_str = '{{"id":1,"method":"begin_recv","params":[{{"file_len":{file_len},"file_name":"air","run_update":true,"md5":"{md5}"}}]}}\r\n'
    fsize = os.path.getsize(file)
    fmd5 = hashlib.md5(file_contents).hexdigest()
    json_str = json_str.format(file_len = fsize, md5 = fmd5)

    s_ota = None
    ota_port = None
    for port in OTA_FILE_PORTS:
        try:
            print(f'Trying OTA file port {port}...')
            s_ota = socket.socket()
            s_ota.settimeout(5)
            s_ota.connect((address, port))
            ota_port = port
            print(f'Connected to OTA file port {port}')
            break
        except (ConnectionRefusedError, socket.timeout, OSError):
            print(f'Port {port} refused')
            s_ota.close()
            s_ota = None

    if s_ota is None:
        print(f'Error: Could not connect to any OTA file port ({", ".join(str(p) for p in OTA_FILE_PORTS)})')
        sys.exit(1)

    s = socket.socket()
    s.connect((address, OTA_COMMAND_PORT))

    version_response = recv_all(s)
    try:
        import json
        version_data = json.loads(version_response)
        print(f'Connected to {version_data.get("name", "ASIAIR")} (v{version_data.get("svr_ver_string", "unknown")})')
    except (json.JSONDecodeError, KeyError):
        print(f'Connected to OTA service')

    print(f'Sending jailbreak payload ({fsize} bytes, md5: {fmd5})...')
    s.sendall(json_str.encode())

    response = recv_all(s)
    try:
        result_data = json.loads(response)
        if result_data.get('result') == 0 and result_data.get('code') == 0:
            print('')
            print('========================================')
            print('  JAILBREAK SUCCESSFUL')
            print('========================================')
            print(f'  Device:   {address}')
            print(f'  OTA port: {ota_port}')
            print('')
            print('  You can now connect via SSH:')
            print(f'    ssh pi@{address}')
            print('    Password: raspberry')
            print('========================================')
        else:
            print('')
            print('========================================')
            print('  JAILBREAK FAILED')
            print('========================================')
            print(f'  Device responded with: {response.strip()}')
            print('========================================')
    except (json.JSONDecodeError, KeyError):
        print(f'Device responded with: {response.strip()}')

    s_ota.sendall(file_contents)

    s_ota.close()
    s.close()


if __name__ == '__main__':
    if len(sys.argv) >= 2 and sys.argv[1] != '--scan':
        address = sys.argv[1]
    else:
        devices = scan_network()

        if not devices:
            print('\nNo ASIAIR devices found on the network.')
            print(f'Usage: {sys.argv[0]} [ASIAIR_IP]')
            print(f'       {sys.argv[0]} --scan')
            sys.exit(1)

        if len(devices) == 1:
            address = devices[0][0]
            info = devices[0][3]
            hostname_str = f' ({info["hostname"]})' if 'hostname' in info else ''
            print(f'\nUsing discovered device: {address}{hostname_str}')
        else:
            print('\nMultiple ASIAIR devices found:')
            for i, (ip, ports, fw, info) in enumerate(devices):
                hostname_str = f' ({info["hostname"]})' if 'hostname' in info else ''
                conf = info['confidence']
                print(f'  [{i + 1}] {ip}{hostname_str} - firmware ~{fw}, confidence: {conf}')
            choice = input('Select device number: ')
            try:
                idx = int(choice) - 1
                address = devices[idx][0]
            except (ValueError, IndexError):
                print('Invalid selection.')
                sys.exit(1)

    print(f'\nConnecting to {address}...')

    open_ports = []
    print(f'Probing ports on {address}...')
    for port in ASIAIR_PORTS:
        if check_port(address, port):
            open_ports.append(port)

    if open_ports:
        has_4801 = 4801 in open_ports
        fw = '10.74+' if has_4801 else '4.35 (or older)'
        info = identify_device(address, open_ports)
        hostname_str = f' ({info["hostname"]})' if 'hostname' in info else ''

        print(f'\n--- Device Identification for {address}{hostname_str} ---')
        if info['is_asiair']:
            print(f'  Device is ASIAIR: YES (confidence: {info["confidence"]})')
        else:
            print(f'  Device is ASIAIR: UNKNOWN (confidence: {info["confidence"]})')
        print(f'  Estimated firmware: {fw}')
        print(f'  Open ports: {", ".join(str(p) for p in open_ports)}')
        for detail in info['details']:
            print(f'  {detail}')
        print('---')

        if not info['is_asiair']:
            print('\nWarning: This device could not be confirmed as an ASIAIR.')
            choice = input('Continue anyway? [y/N] ')
            if choice.lower() != 'y':
                sys.exit(1)
    else:
        print(f'\nWarning: No open ports found on {address}. Device may be offline.')
        choice = input('Continue anyway? [y/N] ')
        if choice.lower() != 'y':
            sys.exit(1)

    if OTA_COMMAND_PORT not in open_ports and open_ports:
        print(f'\nWarning: OTA command port {OTA_COMMAND_PORT} is not open.')
        print('The jailbreak may not work on this firmware version.')
        choice = input('Continue anyway? [y/N] ')
        if choice.lower() != 'y':
            sys.exit(1)

    begin_update(address, JAILBREAK_FILE)
