# Traefik container

The project creates a reverse proxy using Traefik. 

Create a Docker network that all your services ca access. I've chosen to name the une I use in this project `frontend`. The network: `docker network create frontend`.

Start first the Traefix proxy, then the OpenSearch cluster.