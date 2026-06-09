


# build-workspace-image: 
# 	docker build -t workspace:latest -f workspace/Dockerfile workspace

# push-workspace-image: 
# 	docker tag workspace:latest registry.michaelkueller.com/mk/coder-workspace-podman:latest
# 	docker push registry.michaelkueller.com/mk/coder-workspace-podman:latest

build-workspace-image:
	buildah build -t workspace:latest -f workspace/Dockerfile workspace

push-workspace-image:
	buildah tag workspace:latest registry.michaelkueller.com/mk/coder-workspace-podman:latest
	buildah push registry.michaelkueller.com/mk/coder-workspace-podman:latest

debug-workspace-image: 
	docker run \
	--security-opt seccomp=unconfined \
	--security-opt apparmor=unconfined \
	--device /dev/fuse \
	--rm workspace:latest bash -c "podman info"

run: 
	./mvnw spring-boot:run