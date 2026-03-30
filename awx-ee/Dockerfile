FROM quay.io/ansible/awx-ee:latest

USER root

RUN /usr/bin/python3.11 -m pip install --no-cache-dir \
  kubernetes>=26.1.0 \
  openshift>=0.13.1

RUN /usr/bin/python3.11 -c "import kubernetes; print('kubernetes OK')"

RUN mkdir -p /usr/share/ansible/collections && \
  ansible-galaxy collection install \
    kubernetes.core \
    cloud.common \
    ansible.posix \
    -p /usr/share/ansible/collections

ENV ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections
ENV ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3.11

USER 1000
