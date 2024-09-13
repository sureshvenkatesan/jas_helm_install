from ruamel.yaml import YAML
import argparse
import copy

def merge_dicts(a, b):
    """Merge two dictionaries, combining nested dictionaries."""
    if not isinstance(b, dict):
        return b
    result = copy.deepcopy(a)
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

def main(input_file, root_key, output_file):
    yaml = YAML()
    data = load_yaml_file(input_file)

    # Split the root_key into parts to create nested dictionaries
    keys = root_key.split('.')
    nested_data = data
    for key in reversed(keys):
        nested_data = {key: nested_data}

    with open(output_file, 'w') as f:
        yaml.dump(nested_data, f)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Nest YAML content under a specified key while retaining comments.")
    parser.add_argument('input_file', help='The input YAML file')
    parser.add_argument('root_key', help='The root key under which the content will be nested')
    parser.add_argument('-o', '--output', required=True, help='The output YAML file with nested content')

    args = parser.parse_args()
    main(args.input_file, args.root_key, args.output)
