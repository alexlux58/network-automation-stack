#!/usr/bin/env bash
set -euo pipefail
if [ -f .env ]; then
  export $(grep -v '^#' .env | tr '\n' ' ')
fi
echo "Waiting for NetBox and Nautobot to be healthy..."
# Check if services are running first
if ! docker compose ps netbox | grep -q "Up"; then
    echo "NetBox is not running. Please start services first with 'make up' or './scripts/netmgmt.sh start'"
    exit 1
fi
if ! docker compose ps nautobot | grep -q "Up"; then
    echo "Nautobot is not running. Please start services first with 'make up' or './scripts/netmgmt.sh start'"
    exit 1
fi
echo "Ensuring NetBox superuser exists..."
docker compose exec -T netbox /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py shell -c "
from django.contrib.auth import get_user_model
import os
User = get_user_model()
u = os.environ.get('NETBOX_SUPERUSER_NAME', 'admin')
e = os.environ.get('NETBOX_SUPERUSER_EMAIL', 'admin@example.com')
p = os.environ.get('NETBOX_SUPERUSER_PASSWORD', 'admin123!')
if not User.objects.filter(username=u).exists():
    User.objects.create_superuser(username=u, email=e, password=p)
    print('Created NetBox superuser')
else:
    print('NetBox superuser exists, skipping.')
"
echo "Ensuring Nautobot superuser exists..."
docker compose exec -T nautobot sh -lc "
nautobot-server shell -c \"
from django.contrib.auth import get_user_model
import os
User = get_user_model()
u = os.environ.get('NAUTOBOT_SUPERUSER_NAME', 'admin')
e = os.environ.get('NAUTOBOT_SUPERUSER_EMAIL', 'admin@example.com')
p = os.environ.get('NAUTOBOT_SUPERUSER_PASSWORD', 'admin123!')
if not User.objects.filter(username=u).exists():
    User.objects.create_superuser(username=u, email=e, password=p)
    print('Created Nautobot superuser')
else:
    print('Nautobot superuser exists, skipping.')
\"
"
