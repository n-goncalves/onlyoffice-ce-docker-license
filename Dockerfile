ARG product_version=7.2.2
ARG build_number=56
ARG oo_root='/var/www/onlyoffice/documentserver'

## Setup
FROM onlyoffice/documentserver:${product_version}.${build_number} as setup-stage
ARG product_version
ARG build_number
ARG oo_root

ENV PRODUCT_VERSION=${product_version}
ENV BUILD_NUMBER=${build_number}

ARG build_deps="git make g++ nodejs npm"
RUN apt-get update && apt-get install -y ${build_deps}
RUN npm install -g pkg grunt grunt-cli

WORKDIR /build



## Clone
FROM setup-stage as clone-stage
ARG tag=v${PRODUCT_VERSION}.${BUILD_NUMBER}

RUN git clone --quiet --branch $tag --depth 1 https://github.com/ONLYOFFICE/build_tools.git /build/build_tools
RUN git clone --quiet --branch $tag --depth 1 https://github.com/ONLYOFFICE/server.git      /build/server

COPY server.patch /build/server.patch
RUN cd /build/server   && git apply /build/server.patch

# Clone old version of sdk and webapp to get an old version of the mobile editor

ARG tag=v6.3.1.79 # Working mobile editor
RUN git clone --quiet --branch $tag --depth 1 https://github.com/ONLYOFFICE/sdkjs.git       /build/sdkjs
RUN git clone --quiet --branch $tag --depth 1 https://github.com/ONLYOFFICE/web-apps.git    /build/web-apps
COPY web-apps.patch /build/
RUN cd /build/web-apps && git apply /build/web-apps.patch

## Build
FROM clone-stage as build-stage

# build server with license checks patched
WORKDIR /build/server
RUN make
RUN pkg /build/build_tools/out/linux_64/onlyoffice/documentserver/server/FileConverter --targets=node14-linux -o /build/converter
RUN pkg /build/build_tools/out/linux_64/onlyoffice/documentserver/server/DocService --targets=node14-linux --options max_old_space_size=4096 -o /build/docservice

# build web-apps with mobile editing
WORKDIR /build/web-apps/build
RUN npm install
RUN grunt

## Final image
FROM onlyoffice/documentserver:${product_version}.${build_number}
ARG oo_root

#server
COPY --from=build-stage /build/converter  ${oo_root}/server/FileConverter/converter
COPY --from=build-stage /build/docservice ${oo_root}/server/DocService/docservice

# Restore mobile editing using an old version of mobile editor (add dependencies that were removed in desktop editor)
COPY --from=build-stage /build/web-apps/vendor/jszip                                   ${oo_root}/web-apps/vendor/jszip
COPY --from=build-stage /build/web-apps/vendor/jszip-utils                             ${oo_root}/web-apps/vendor/jszip-utils
COPY --from=build-stage /build/web-apps/deploy/web-apps/apps/documenteditor/mobile     ${oo_root}/web-apps/apps/documenteditor/mobile
COPY --from=build-stage /build/web-apps/deploy/web-apps/apps/presentationeditor/mobile ${oo_root}/web-apps/apps/presentationeditor/mobile
COPY --from=build-stage /build/web-apps/deploy/web-apps/apps/spreadsheeteditor/mobile  ${oo_root}/web-apps/apps/spreadsheeteditor/mobile
