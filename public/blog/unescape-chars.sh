#!/bin/bash

# Define the directory containing your files
DIRECTORY="./"

# Define the characters to replace
declare -A html_entities=(
	["""]="\""
	["&amp;"]="&"
	["<"]="<"
	[">"]=">"
	["'"]="'"
	["'"]="'"
	["""]="\""
	["&#38;"]="&"
	["<"]="<"
	[">"]=">"
	["+"]="+"
)

# Iterate over all files in the directory
for file in "$DIRECTORY"/*; do
	if [[ -f $file ]]; then
		# Read the file and replace escape characters
		for entity in "${!html_entities[@]}"; do
			sed -i "s/$entity/${html_entities[$entity]}/g" "$file"
		done
		echo "Processed $file"
	fi
done
