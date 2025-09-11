
rancher-docker-nginx/
├── docker-compose.yml
├── .env
├── .gitignore
├── scripts/
│   ├── keycloak-demo.sh
│   ├── backup.sh
│   ├── restore.sh
│   └── health-check.sh
├── config/
│   ├── nginx/
│   │   ├── nginx.conf
│   │   └── conf.d/
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   └── rules/
│   ├── grafana/
│   │   └── provisioning/
│   └── certs/
├── data/
│   ├── nginx/
│   ├── keycloak/
│   ├── postgres/
│   ├── wikijs/
│   ├── wikijs-postgres/
│   ├── prometheus/
│   ├── grafana/
│   ├── rancher/
│   └── webapp/
├── webapp/
│   ├── app.py
│   ├── Dockerfile
│   ├── requirements.txt
│   └── templates/
└── guides/
    ├── README.md
    ├── SETUP.md
    ├── TROUBLESHOOTING.md
    └── API.md