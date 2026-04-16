FROM ghcr.io/loong64/debian:trixie AS base

# runtime dependencies
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		ca-certificates \
		ccache \
		build-essential \
		cmake \
		git \
		libssl-dev \
	; \
	apt-get install -y gcc-14 g++-14; \
	apt-get dist-clean

ENV CC=gcc-14 CXX=g++-14
ENV CMAKE_ARGS="-DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_TOOLS=ON -DLLAMA_BUILD_SERVER=ON -DGGML_RPC=ON"

ARG VERSION
ENV VERSION=${VERSION}
WORKDIR /data/llama.cpp

RUN set -eux; \
	mkdir -p /dist; \
	git clone --depth 1 -b ${VERSION} https://github.com/ggml-org/llama.cpp /data/llama.cpp

FROM base AS build-cpu

# build cpu
RUN --mount=type=cache,target=/root/.cache/ccache \
	set -eux; \
	cmake -B build \
		-DCMAKE_INSTALL_RPATH='$ORIGIN' \
		-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
		-DGGML_BACKEND_DL=ON \
		-DGGML_NATIVE=OFF \
		-DLLAMA_FATAL_WARNINGS=ON \
		${CMAKE_ARGS} \
	; \
	cmake --build build --config Release -j $(nproc);\
	cp LICENSE ./build/bin/; \
	tar -czvf /dist/llama-${VERSION}-bin-debian-loong64.tar.gz --transform "s,./,llama-${VERSION}/," -C ./build/bin .

FROM base AS build-vulkan

# vulkan dependencies
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	set -eux; \
	apt-get update; \
	apt-get install -y \
		glslc \
		libvulkan-dev \
		spirv-headers \
		ninja-build \
	; \
	apt-get dist-clean

# build vulkan
RUN --mount=type=cache,target=/root/.cache/ccache \
	set -eux; \
	cmake -B build \
		-DCMAKE_INSTALL_RPATH='$ORIGIN' \
		-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
		-DGGML_BACKEND_DL=ON \
		-DGGML_NATIVE=OFF \
		-DGGML_VULKAN=ON \
		${CMAKE_ARGS} \
	; \
	cmake --build build --config Release -j $(nproc); \
	cp LICENSE ./build/bin/; \
	tar -czvf /dist/llama-${VERSION}-bin-debian-vulkan-loong64.tar.gz --transform "s,./,llama-${VERSION}/," -C ./build/bin .

FROM scratch
COPY --from=build-cpu /dist/ /dist/
COPY --from=build-vulkan /dist/ /dist/