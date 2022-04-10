#!/bin/bash

GODOT=/opt/Godot_v4.0-alpha6_linux.64

$GODOT --server &
sleep "1.$(($RANDOM % 10))s"
$GODOT
