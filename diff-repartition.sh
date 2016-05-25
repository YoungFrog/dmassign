#!/bin/bash
diff -u <(grep -o '^Th.*' $1 | sort) <(grep -o '^Th.*' $2 | sort)

