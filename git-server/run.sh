
docker run -d -p 9418:9418 -v  /srv/git:/git --name git_server apline311:git-server


# test

echo you can use git clone command: git clone git://127.0.0.1/\$project_name

