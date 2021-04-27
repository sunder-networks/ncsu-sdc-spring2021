
docker run -d -p 50000-50030:50000-50030 -p 3000:3000 --name=influxdb quay.io/influxdb/influxdb:1.6-alpine

docker run -d --net=container:influxdb  --name grafana grafana/grafana:6.5.0
# grafana dashboard: 12751



docker run -d --name=telegraf  --net=container:grafana -v $PWD/telegraf.conf:/etc/telegraf/telegraf.conf:ro telegraf


