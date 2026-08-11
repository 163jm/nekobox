cmake_minimum_required(VERSION 3.10)
project(tunfwd C)

# VpnService tun fd 传递 + sing-box 子进程启动(仅 arm64-v8a 构建)
add_library(tunfwd SHARED tun_fwd.c)

target_compile_options(tunfwd PRIVATE -O2 -Wall)
