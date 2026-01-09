###############################################################
#                     Waenara / SCPSL-Egg                     #
#   Pterodactyl egg for simplified SCP:SL server management   #
#         Created by Waenara -- waenara.dev@gmail.com         #
###############################################################

FROM ubuntu:24.04

LABEL maintainer="waenara.dev@gmail.com"
LABEL description="SCP:Secret Laboratory server container"

# Установка всех необходимых зависимостей одним слоем
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    lib32gcc-s1 \
    libicu-dev \
    unzip \
    && rm -rf /var/lib/apt/lists/* && \
    apt-get clean && \
    update-ca-certificates && \
    useradd -m -d /home/container -s /bin/bash container

USER container
ENV USER=container \
    HOME=/home/container

WORKDIR /home/container

COPY --chown=container:container ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/bin/bash", "/entrypoint.sh"]