# iDrive e360 Docker container
# Based on Ubuntu which iDrive officially supports
FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    perl \
    unzip \
    cron \
    ca-certificates \
    libsqlite3-0 \
    libexpat1 \
    libbz2-1.0 \
    liblzma5 \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for running backups
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN groupadd -g ${GROUP_ID} idrive && \
    useradd -m -u ${USER_ID} -g idrive -s /bin/bash idrive

WORKDIR /tmp

# Copy the local deb file (must be named IDrive360.deb in build context)
COPY IDrive360.deb /tmp/idrive360.deb

# Install the package
RUN dpkg -i idrive360.deb || apt-get install -f -y && \
    rm -f idrive360.deb

# Create service directory for iDrive data
RUN mkdir -p /opt/idrive360/idriveIt

# Volume mount points:
# - /data: Directory to backup (mount your actual data here)
# - /opt/idrive360/idriveIt: iDrive service data (persist this)
VOLUME ["/data", "/opt/idrive360/idriveIt"]

WORKDIR /opt/idrive360

# The iDrive scripts are installed in /opt/idrive360
ENV PATH="/opt/idrive360:${PATH}"

# Run as root (e360 Python binary requires root)
# Entry point for interactive setup
CMD ["perl", "account_setting.pl"]
