#!/bin/zsh

git add .
git commit -v -a -m "fix schema for kong 1.1"
git push origin master

git tag -d 0.3.3
git tag 0.3.3
git push origin 0.3.3 -f

luarocks upload kong-plugin-mithril-0.3.3-1.rockspec --api-key=yQVKTMr1pujot4kmpSnM1gLjGUEYfqd2iN7eVf3a --force
