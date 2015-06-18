#!/bin/bash -e

cd $(dirname $0)

. utils
. ../../environment

osc create -f - <<EOF
kind: List
apiVersion: v1beta3
items:
- kind: ReplicationController
  apiVersion: v1beta3
  metadata:
    name: jenkins
    labels:
      component: jenkins
  spec:
    replicas: 1
    selector:
      component: jenkins
    template:
      metadata:
        labels:
          component: jenkins
      spec:
        containers:
        - name: jenkins
          image: docker.io/cicddemo/jenkins
          imagePullPolicy: IfNotPresent
          ports:
          - containerPort: 8080
          - containerPort: 50000
          securityContext:
            privileged: true
          volumeMounts:
          - mountPath: /var/run/docker.sock
            name: docker-socket
        volumes:
        - hostPath:
            path: /var/run/docker.sock
          name: docker-socket

- kind: Service
  apiVersion: v1beta3
  metadata:
    name: jenkins
    labels:
      component: jenkins
  spec:
    ports:
    - port: 8080
    selector:
      component: jenkins

- kind: Route
  apiVersion: v1beta1
  metadata:
    name: jenkins
    labels:
      component: jenkins
  host: jenkins.$DOMAIN
  serviceName: jenkins
EOF

while true; do
  PODIP=$(osc get pods -l component=jenkins --template='{{(index .items 0).status.podIP}}' 2>/dev/null)
  if [ "$PODIP" != '<no value>' -a "${PODIP:0:5}" != 'Error' ]; then
    break
  fi
  sleep 1
done

while ! curl -fsm 1 -o /dev/null $PODIP:8080; do
  sleep 1
done

[ -e /tmp/jenkins-cli.jar ] || curl -so /tmp/jenkins-cli.jar http://$PODIP:8080/jnlpJars/jenkins-cli.jar

for i in job-*.xml; do
  java -jar /tmp/jenkins-cli.jar -s http://$PODIP:8080/ create-job "$(echo $i | sed -e 's/^job-..-//; s/.xml$//')" < "$i" 2>/dev/null
done

for i in view-*.xml; do
  java -jar /tmp/jenkins-cli.jar -s http://$PODIP:8080/ create-view "$(echo $i | sed -e 's/^view-..-//; s/.xml$//')" < "$i" 2>/dev/null
done