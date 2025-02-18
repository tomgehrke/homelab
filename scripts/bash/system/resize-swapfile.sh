#!/bin/bash

sudo swapoff /swapfile
sudo fallocate -l 1G /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
