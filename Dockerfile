# --- Stage 1: Build the esmd binary ---
FROM registry.redhat.io/rhel8/go-toolset AS builder

# Set to root user for package installation
USER root

ARG SERVER_VERSION="v136"
# Install necessary packages
RUN dnf install -y git && \
    dnf clean all

RUN cat /certs/AXA-Enterprise-Root-CA.pem && \
    cat /certs/AXA-Proxy-ROOT-CA.pem && \
    cp /certs/AXA-Enterprise-Root-CA.pem /etc/pki/ca-trust/source/anchors/ && \
    cp /certs/AXA-Proxy-ROOT-CA.pem /etc/pki/ca-trust/source/anchors/

RUN echo "I am here"  && \
    ls /etc/pki/ca-trust/source/anchors/
    
# Inject AXA root CA and Proxy CA certificate into RHEL based base image
# COPY [ "/certs/AXA-Enterprise-Root-CA.pem", "/certs/AXA-Proxy-ROOT-CA.pem", "/etc/pki/ca-trust/source/anchors/" ]
RUN update-ca-trust extract
ENV REQUESTS_CA_BUNDLE=/etc/pki/tls/cert.pem

RUN go version || echo "Go is not installed"

# Clone the repository
RUN git clone --branch $SERVER_VERSION --depth 1 https://github.com/esm-dev/esm.sh /tmp/esm.sh
WORKDIR /tmp/esm.sh
RUN ls -lhatr
# Build the esmd binary
RUN go build -ldflags="-s -w -X 'github.com/esm-dev/esm.sh/server.VERSION=${SERVER_VERSION}'" -o esmd ./server/esmd/main.go

# --- Stage 2: Obtain the Deno binary ---
FROM registry.access.redhat.com/ubi8/ubi:latest

# Set to root user for package installation
USER root

# Install necessary packages
RUN dnf install -y curl unzip && dnf clean all

# Inject AXA root CA and Proxy CA certificate into RHEL based base image
COPY [ "/certs/AXA-Enterprise-Root-CA.pem", "/certs/AXA-Proxy-ROOT-CA.pem", "/etc/pki/ca-trust/source/anchors/" ]
RUN update-ca-trust extract
ENV REQUESTS_CA_BUNDLE=/etc/pki/tls/cert.pem
# Set Deno version
ENV DENO_VERSION=2.1.4

# Download and install Deno
RUN curl -fsSL https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-x86_64-unknown-linux-gnu.zip -o deno.zip && \
    unzip deno.zip && \
    rm deno.zip && \
    chmod +x deno && \
    mv deno /usr/local/bin/

# Verify installation
RUN deno --version

# --- Stage 3: Create the final image ---
FROM registry.access.redhat.com/ubi8/ubi-minimal:latest

# Set to root user for package installation
USER root

# Install necessary packages
RUN microdnf install -y git shadow-utils && \
    microdnf clean all
# Inject AXA root CA and Proxy CA certificate into RHEL based base image
COPY [ "/certs/AXA-Enterprise-Root-CA.pem", "/certs/AXA-Proxy-ROOT-CA.pem", "/etc/pki/ca-trust/source/anchors/" ]
RUN update-ca-trust extract
ENV REQUESTS_CA_BUNDLE=/etc/pki/tls/cert.pem

# Add user and create working directory
RUN groupadd -g 1000 esm && \
    useradd -u 1000 -g esm -d /esmd -m esm

# Copy esmd binary from the builder stage
COPY --from=builder /tmp/esm.sh/esmd /bin/esmd

# Set environment variables
ENV ESMPORT="8080"
ENV ESMDIR="/esmd"

# Set permissions
RUN chown -R esm:esm /esmd

# Switch to non-root user
USER esm

# Expose port and set working directory
EXPOSE 8080
WORKDIR /esmd

# Command to run the application
CMD ["/bin/esmd"]
