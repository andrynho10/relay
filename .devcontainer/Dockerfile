# syntax=docker/dockerfile:1
# Development image (ADR-0009). Every tool is pinned to an exact version and every download is
# verified against the vendor's published checksum or signature. Versions are bumped in their own
# PR, a couple of weeks after a release.
FROM mcr.microsoft.com/devcontainers/python:3.2.6-3.14-trixie@sha256:28835c112fd097cb6d2fe1e195b660d66ae051859070a9b871fa2308f35897d3

ARG TARGETARCH

ARG NODE_VERSION=24.21.0
ARG NODE_SHA256_AMD64=fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6
ARG NODE_SHA256_ARM64=6ad1325edbdb5649c379b75a237147a666c95d4f9ae8d340fef2d1575d289ad2

ARG TERRAFORM_VERSION=1.16.4
ARG TERRAFORM_SHA256_AMD64=dc94af0eef1147718ad7c8daea792ed199e3e0492eec180d0adafa2a65a879df
ARG TERRAFORM_SHA256_ARM64=8263f301cb1a24489a4adeed147bf28504053f77237b3ea97a0ef2972659de30

ARG GH_VERSION=2.101.0
ARG GH_SHA256_AMD64=9bca2d1c16825f109907a23307628a2f0698fbf99662b73a5cf0b020293072b8
ARG GH_SHA256_ARM64=b57e8063f18862647c9d22727c32e9da1b963f8bf9db648fe123a6975695640f

# AWS CLI zips are PGP-signed; the key and fingerprint come from the AWS CLI install guide.
ARG AWSCLI_VERSION=2.37.6
ARG AWSCLI_SIGNER_FINGERPRINT=FB5DB77FD5C118B80511ADA8A6310ACC4672475C

ARG PRE_COMMIT_VERSION=4.6.2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY --from=ghcr.io/astral-sh/uv:0.12.21@sha256:a7aed3216253ee804de3e2d8afa5073baa1a177335345d43845cd4165e43b711 /uv /uvx /usr/local/bin/

RUN case "${TARGETARCH}" in \
      amd64) arch=x64;   sha="${NODE_SHA256_AMD64}" ;; \
      arm64) arch=arm64; sha="${NODE_SHA256_ARM64}" ;; \
      *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSLo /tmp/node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${arch}.tar.xz" \
 && echo "${sha}  /tmp/node.tar.xz" | sha256sum -c - \
 && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner \
      --exclude='*/CHANGELOG.md' --exclude='*/LICENSE' --exclude='*/README.md' \
 && rm /tmp/node.tar.xz

RUN case "${TARGETARCH}" in \
      amd64) sha="${TERRAFORM_SHA256_AMD64}" ;; \
      arm64) sha="${TERRAFORM_SHA256_ARM64}" ;; \
      *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSLo /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" \
 && echo "${sha}  /tmp/terraform.zip" | sha256sum -c - \
 && unzip -q /tmp/terraform.zip terraform -d /usr/local/bin \
 && rm /tmp/terraform.zip

RUN case "${TARGETARCH}" in \
      amd64) sha="${GH_SHA256_AMD64}" ;; \
      arm64) sha="${GH_SHA256_ARM64}" ;; \
      *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSLo /tmp/gh.tar.gz "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" \
 && echo "${sha}  /tmp/gh.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/gh.tar.gz -C /tmp \
 && install -m 0755 "/tmp/gh_${GH_VERSION}_linux_${TARGETARCH}/bin/gh" /usr/local/bin/gh \
 && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_${TARGETARCH}"

COPY aws-cli-public-key.asc /tmp/aws-cli-public-key.asc
RUN case "${TARGETARCH}" in \
      amd64) arch=x86_64 ;; \
      arm64) arch=aarch64 ;; \
      *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && export GNUPGHOME="$(mktemp -d)" \
 && gpg --batch --quiet --import /tmp/aws-cli-public-key.asc \
 && gpg --batch --with-colons --fingerprint | grep -q "^fpr:::::::::${AWSCLI_SIGNER_FINGERPRINT}:$" \
 && url="https://awscli.amazonaws.com/awscli-exe-linux-${arch}-${AWSCLI_VERSION}.zip" \
 && curl -fsSLo /tmp/awscli.zip "${url}" \
 && curl -fsSLo /tmp/awscli.zip.sig "${url}.sig" \
 && gpg --batch --verify /tmp/awscli.zip.sig /tmp/awscli.zip \
 && unzip -q /tmp/awscli.zip -d /tmp \
 && /tmp/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin \
 && rm -rf /tmp/aws /tmp/awscli.zip /tmp/awscli.zip.sig /tmp/aws-cli-public-key.asc "${GNUPGHOME}"

# Install pre-commit as a uv tool outside any user's home so it survives volume mounts.
RUN UV_TOOL_DIR=/usr/local/share/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
      uv tool install --no-cache "pre-commit==${PRE_COMMIT_VERSION}"
