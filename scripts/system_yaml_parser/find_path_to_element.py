import argparse
import yaml
import json
"""
Usage: python find_path_to_element.py artifactory_default_system.yaml metrics  
https://yaql.readthedocs.io/en/latest/getting_started.html
 https://wiki.openstack.org/wiki/Mistral/UsingYAQL -> http://yaqluator.ovh/

Output:
[
    "shared.metrics",
    "artifactory.metrics",
    "access.metrics",
    "event.metrics",
    "event.logging.metrics",
    "integration.metrics",
    "integration.logging.metrics",
    "observability.metrics",
    "observability.logging.metrics"
]
"""
def find_path_to_key(data, key, current_path=""):
    if isinstance(data, dict):
        for k, v in data.items():
            if k == key:
                yield current_path + k
            else:
                yield from find_path_to_key(v, key, current_path + k + '.')
    elif isinstance(data, list):
        for i, item in enumerate(data):
            yield from find_path_to_key(item, key, current_path + str(i) + '.')

def main():
    parser = argparse.ArgumentParser(description='Find the path to a key in dot notation in a YAML file.')
    parser.add_argument('yaml_file', type=str, help='Path to the YAML file')
    parser.add_argument('key', type=str, help='Key to search for in the YAML file')
    args = parser.parse_args()

    # Load and parse the YAML data
    with open(args.yaml_file, 'r') as yaml_file:
        data = yaml.safe_load(yaml_file)

    # Find the paths to the specified key
    paths_list = list(find_path_to_key(data, args.key))

    # Output the result as JSON
    print(json.dumps(paths_list, indent=4))

if __name__ == '__main__':
    main()
