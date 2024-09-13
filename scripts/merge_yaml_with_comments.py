from ruamel.yaml import YAML
import argparse

def merge_dicts(a, b):
    """Merge two dictionaries, combining nested dictionaries."""
    if not isinstance(b, dict):
        return b
    result = dict(a)
    for k, v in b.items():
        if k in result and isinstance(result[k], dict):
            result[k] = merge_dicts(result[k], v)
        else:
            result[k] = v
    return result

def load_yaml_file(filename):
    """Load a YAML file, preserving comments."""
    yaml = YAML()
    with open(filename, 'r') as f:
        return yaml.load(f)

def main(input_files, output_file):
    yaml = YAML()
    merged_yaml = {}
    
    for file in input_files:
        yaml_content = load_yaml_file(file)
        merged_yaml = merge_dicts(merged_yaml, yaml_content)
    
    with open(output_file, 'w') as f:
        yaml.dump(merged_yaml, f)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Merge YAML files while retaining comments.")
    parser.add_argument('input_files', nargs='+', help='List of input YAML files to be merged')
    parser.add_argument('-o', '--output', required=True, help='Output file to save the merged YAML content')

    args = parser.parse_args()
    main(args.input_files, args.output)
