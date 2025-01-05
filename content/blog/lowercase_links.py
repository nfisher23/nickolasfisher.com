import os
import re


def lowercase_links_in_file(file_path):
    with open(file_path, "r", encoding="utf-8") as file:
        content = file.read()

    # Regular expression to find URLs with the domain containing "nickolasfisher"
    url_pattern = re.compile(
        r"https?://(?:www\.)?nickolasfisher\.com[^\s\)]+", re.IGNORECASE
    )

    # Function to lowercase matched URLs
    def lowercase_url(match):
        return match.group(0).lower()

    # Replace URLs with lowercase versions
    updated_content = url_pattern.sub(lowercase_url, content)

    # Write the updated content back to the file
    with open(file_path, "w", encoding="utf-8") as file:
        file.write(updated_content)


def process_directory(directory):
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith(".md"):
                file_path = os.path.join(root, file)
                print(f"Processing file: {file_path}")
                lowercase_links_in_file(file_path)


if __name__ == "__main__":
    # Set the directory path to the current directory
    directory_path = "./"
    process_directory(directory_path)
