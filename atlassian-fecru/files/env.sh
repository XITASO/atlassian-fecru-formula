#!/bin/sh
export JAVA_HOME={{ config.java_home }}
export FISHEYE_INST={{ config.dirs.home }}
export FISHEYE_OPTS="{{ config.fisheye_opts }} ${FISHEYE_OPTS}"
