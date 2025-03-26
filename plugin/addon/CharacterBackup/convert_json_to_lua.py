import json

# Replace 'output.json' with the filename you exported from SQLyog
with open('output.json', 'r', encoding='utf8') as infile:
    data = json.load(infile)

with open('output.lua', 'w', encoding='utf8') as outfile:
    outfile.write("local spells = {\n")
    for row in data:
        # Create a Lua table for each row. Adjust field names as needed.
        entry = "  {"
        entry += ", ".join([f'{key} = {json.dumps(value)}' for key, value in row.items()])
        entry += "},\n"
        outfile.write(entry)
    outfile.write("}\n\nreturn spells\n")
