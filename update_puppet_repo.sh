#!/bin/bash

[ "$(ssh-add -l 2>/dev/null|wc -l)" -eq 0 ] && { echo "must have a ssh agent with a github key loaded before this will work"; exit 1; }

cd /etc/puppet/puppet_repo
sudo -E git pull
sudo -E git submodule init
sudo -E git submodule update
