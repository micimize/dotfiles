#!/bin/bash
for rc in .*rc;
do
	ln $rc ~/$rc;
done
