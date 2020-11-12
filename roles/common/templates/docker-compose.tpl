version: '3.7'
services:
  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: always
    environment:
      TZ: {{ timezone }}
      WATCHTOWER_SCHEDULE: '0 0 0 * * *'
      WATCHTOWER_CLEANUP: 'true'
      WATCHTOWER_NOTIFICATIONS: slack
      WATCHTOWER_NOTIFICATION_SLACK_HOOK_URL: ${WATCHTOWER_SLACK_HOOK_URL}
      WATCHTOWER_NOTIFICATION_SLACK_IDENTIFIER: watchtower
      WATCHTOWER_NOTIFICATION_SLACK_CHANNEL: '#hosting'
      WATCHTOWER_DEBUG: '${WATCHTOWER_DEBUG:-false}'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    ports:
      - '9090:9090'
    environment:
      TZ: {{ timezone }}
    volumes:
      - prometheus:/prometheus
      - '{{ root_path }}/prometheus:/etc/prometheus'
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=168h'
      - '--web.enable-lifecycle'
  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    restart: unless-stopped
    expose:
      - 9093
    volumes:
      - '{{ root_path }}/alertmanager:/etc/alertmanager'
    command:
      - '--config.file=/etc/alertmanager/config.yml'
      - '--storage.path=/alertmanager'
  pushgateway:
    image: prom/pushgateway:latest
    container_name: pushgateway
    restart: unless-stopped
    expose:
      - 9091
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - '3000:3000'
    environment:
      TZ: {{ timezone }}
      GF_SECURITY_ADMIN_USER: ${GRAFANA_USER}
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD}
      GF_USERS_ALLOW_SIGN_UP: 'false'
      GF_INSTALL_PLUGINS: grafana-piechart-panel
    volumes:
      - grafana:/var/lib/grafana
      - '{{ root_path }}/grafana/provisioning:/etc/grafana/provisioning'
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    expose:
      - 9100
    volumes:
      - /:/rootfs:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)'
  unifi-exporter:
    image: jessestuart/unifi_exporter:latest
    container_name: unifi-exporter
    restart: unless-stopped
    depends_on:
      - unifi
    expose:
      - 9130
    volumes:
      - '{{ root_path }}/unifi-exporter/config.yml:/etc/unifi-exporter/config.yml:ro'
    command: '-config.file=/etc/unifi-exporter/config.yml'
  pihole-exporter:
    image: ekofr/pihole-exporter:0.0.10
    container_name: pihole-exporter
    restart: unless-stopped
    depends_on:
      - pihole
    expose:
      - 9617
    environment:
      PIHOLE_HOSTNAME: ${CONTROLLER_IP}
      PIHOLE_PASSWORD: ${PI_HOLE_PASSWORD}
  dozzle:
    image: amir20/dozzle:latest
    container_name: dozzle
    restart: always
    depends_on:
      - pihole
    ports:
      - 9001:8080
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    depends_on:
      - pihole
    command: -H unix:///var/run/docker.sock --no-analytics --ssl --sslcert /data/fullchain.pem --sslkey /data/privkey.pem
    ports:
      - '9000:9000'
      - '8000:8000'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - '{{ root_path }}/portainer:/data'
  unifi:
    image: ryansch/unifi-rpi:latest
    container_name: unifi
    restart: unless-stopped
    depends_on:
      - pihole
    network_mode: host
    volumes:
      - '{{ root_path }}/unifi/config:/var/lib/unifi'
      - '{{ root_path }}/unifi/log:/usr/lib/unifi/logs'
      - '{{ root_path }}/unifi/log2:/var/log/unifi'
      - '{{ root_path }}/unifi/run:/usr/lib/unifi/run'
      - '{{ root_path }}/unifi/run2:/run/unifi'
      - '{{ root_path }}/unifi/work:/usr/lib/unifi/work'
  pihole:
    image: pihole/pihole:latest
    container_name: pihole
    restart: unless-stopped
    depends_on:
      - cloudflared
    ports:
      - '53:53/tcp'
      - '53:53/udp'
      - '67:67/udp'
      - '80:80/tcp'
      - '443:443/tcp'
    environment:
      ServerIP: ${CONTROLLER_IP}
      TZ: {{ timezone }}
      VIRTUAL_PORT: 80
      DNS1: 172.20.0.2#5053
      DNS2: 'no'
      DNS_FQDN_REQUIRED: 'true'
      WEBPASSWORD: ${PI_HOLE_PASSWORD}
      CONDITIONAL_FORWARDING: 'true'
      CONDITIONAL_FORWARDING_IP: ${ROUTER_IP}
      CONDITIONAL_FORWARDING_DOMAIN: fritz.box
      PROXY_LOCATION: pihole
      WEBUIBOXEDLAYOUT: traditional
      TEMPERATUREUNIT: c
    volumes:
      - '{{ root_path }}/pihole/etc-pihole/:/etc/pihole/'
      - '{{ root_path }}/pihole/etc-dnsmasq.d/:/etc/dnsmasq.d/'
      - '{{ root_path }}/pihole/themes/pi-hole-midnight/skin-blue.min.css:/var/www/html/admin/style/vendor/skin-blue.min.css'
    dns:
      - 127.0.0.1
      - 1.1.1.1
    networks:
      default:
        ipv4_address: 172.20.0.3
    cap_add:
      - NET_ADMIN
  cloudflared:
    image: crazymax/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    ports:
      - '5053:5053/udp'
      - '49312:49312/tcp'
    environment:
      TZ: {{ timezone }}
      TUNNEL_DNS_UPSTREAM: https://1.1.1.1/dns-query,https://1.0.0.1/dns-query
    networks:
      default:
        ipv4_address: 172.20.0.2
  homeassistant:
    image: homeassistant/home-assistant:stable
    container_name: homeassistant
    restart: unless-stopped
    depends_on:
      - pihole
    network_mode: host
    environment:
      TZ: {{ timezone }}
    volumes:
      - '{{ root_path }}/home-assistant:/config'
networks:
  default:
    ipam:
      config:
        - subnet: 172.20.0.0/24
volumes:
  prometheus:
  grafana: