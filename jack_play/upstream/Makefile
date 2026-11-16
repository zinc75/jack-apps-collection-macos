all:
	echo "rju"

install:
	cabal v1-install --allow-newer

clean:
	rm -fR dist dist-newstyle *~
	(cd cmd ; make clean)

mk-cmd:
	(cd cmd ; make all install)

push-all:
	r.gitlab-push.sh rju
	r.github-push.sh rju

debian:
	sudo apt-get install liblo-dev libsamplerate0-dev
