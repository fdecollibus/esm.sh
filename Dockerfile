# --- build server from source code

FROM registry.redhat.io/rhel8/go-toolset AS builder

ARG SERVER_VERSION="v136"

# Install necessary packages using dnf

RUN dnf install -y git && \

    dnf clean all

# Clone the repository

RUN git clone --branch $SERVER_VERSION --depth 1 https://github.com/esm-dev/esm.sh /tmp/esm.sh

WORKDIR /tmp/esm.sh

# Build the application

RUN go build -ldflags="-s -w -X 'github.com/esm-dev/esm.sh/server.VERSION=${SERVER_VERSION}'" -o esmd server/esmd/main.go

# ---

# Use Red Hat UBI Minimal as the base image

FROM registry.access.redhat.com/ubi8/ubi-minimal:latest

# Install necessary packages using microdnf

RUN microdnf install -y git shadow-utils && \

    microdnf clean all

# Add user and create working directory

RUN groupadd -g 1000 esm && \

    useradd -u 1000 -g esm -d /esmd -m esm

# Copy esmd binary from the builder stage

COPY --from=builder /tmp/esm.sh/esmd /bin/esmd

# Copy deno binary from the official deno image

COPY --from=denoland/deno:bin-2.1.4 /deno /esmd/bin/deno

# Set environment variables

ENV ESMPORT="8080"

ENV ESMDIR="/esmd"

# Set permissions

RUN chown -R esm:esm /esmd

# Switch to non-root user

USER esm

EXPOSE 8080

WORKDIR /esmd

CMD ["/bin/esmd"] 
