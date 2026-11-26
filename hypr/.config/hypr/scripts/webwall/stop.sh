#!/usr/bin/env bash
systemctl --user stop webwall-trial 2>/dev/null
skwd-helm resume >/dev/null
