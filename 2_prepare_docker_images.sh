#!/bin/bash 
set -euo pipefail

. utils.sh

: "${SEEDFETCHER_IMAGE:=cyberark/dap-seedfetcher}"

main() {
  if [[ "${PLATFORM}" = "openshift" ]]; then
    docker login -u _ -p $(oc whoami -t) $DOCKER_REGISTRY_PATH
  fi

  if [[ $CONJUR_DEPLOYMENT == oss ]]; then
    echo "Prepare Conjur OSS cluster"
    prepare_conjur_oss_cluster
  else
    echo "Prepare DAP cluster"
    prepare_conjur_appliance_image
    prepare_seed_fetcher_image
  fi

  if [[ "${DEPLOY_MASTER_CLUSTER}" = "true" ]]; then
    prepare_conjur_cli_image
  fi

  echo "Docker images pushed."
}

prepare_conjur_appliance_image() {
  announce "Tagging and pushing Conjur appliance"

  conjur_appliance_image=$(platform_image conjur-appliance)

  # Try to pull the image if we can
  docker pull $CONJUR_APPLIANCE_IMAGE || true
  docker tag $CONJUR_APPLIANCE_IMAGE $conjur_appliance_image

  if [ ! is_minienv ] || [ "${DEV}" = "false" ] ; then
    docker push $conjur_appliance_image
  fi
}

prepare_conjur_cli_image() {
  announce "Pulling and pushing Conjur CLI image."

  docker pull cyberark/conjur-cli:$CONJUR_VERSION-latest
  docker tag cyberark/conjur-cli:$CONJUR_VERSION-latest conjur-cli:$CONJUR_NAMESPACE_NAME

  cli_app_image=$(platform_image conjur-cli)
  docker tag conjur-cli:$CONJUR_NAMESPACE_NAME $cli_app_image

  if [ ! is_minienv ] || [ "${DEV}" = "false" ]; then
    docker push $cli_app_image
  fi
}

prepare_seed_fetcher_image() {
  announce "Pulling and pushing seed-fetcher image."

  docker pull $SEEDFETCHER_IMAGE

  seedfetcher_image=$(platform_image seed-fetcher)
  docker tag $SEEDFETCHER_IMAGE $seedfetcher_image

  if [ ! is_minienv ] || [ "${DEV}" = "false" ]; then
    docker push $seedfetcher_image
  fi
}

prepare_conjur_oss_cluster() {
  announce "Pulling and pushing Conjur OSS image."

  # Allow using local conjur images for deployment
  if [[ -z "${LOCAL_CONJUR_IMAGE}" ]]; then
    conjur_oss_image="registry.tld/conjur:1-stable"
    docker pull $conjur_oss_image
  else
    conjur_oss_image="${LOCAL_CONJUR_IMAGE}"
  fi

  conjur_platform_oss_image=$(platform_image "conjur")
  docker tag "$conjur_oss_image" $conjur_platform_oss_image

  if [ "${DEV}" = "false" ]; then
    echo "Pushing Conjur image ${conjur_platform_oss_image} to repo..."
    docker push $conjur_platform_oss_image
  fi

  announce "Pulling and pushing Nginx image."

  nginx_image=$(platform_image "nginx")
  # Push nginx image to openshift repo
  pushd oss/nginx_base
    sed -i -e "s#{{ CONJUR_NAMESPACE_NAME }}#$CONJUR_NAMESPACE_NAME#g" ./proxy/ssl.conf
    docker build -t $nginx_image .

    if [ "${DEV}" = "false" ]; then
      docker push $nginx_image
    fi
  popd
}

main $@
