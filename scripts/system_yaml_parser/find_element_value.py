import argparse
import yaml
import json

"""
Usage: python find_element_value.py artifactory_default_system.yaml metrics
https://yaql.readthedocs.io/en/latest/getting_started.html
 https://wiki.openstack.org/wiki/Mistral/UsingYAQL -> http://yaqluator.ovh/
"""
def find_elements_by_key(data, key):
    if isinstance(data, dict):
        for k, v in data.items():
            if k == key:
                yield v
            else:
                yield from find_elements_by_key(v, key)
    elif isinstance(data, list):
        for item in data:
            yield from find_elements_by_key(item, key)

def main():
    parser = argparse.ArgumentParser(description='Find elements by key in a YAML file.')
    parser.add_argument('yaml_file', type=str, help='Path to the YAML file')
    parser.add_argument('key', type=str, help='Key to search for in the YAML file')
    args = parser.parse_args()

    # Load and parse the YAML data
    with open(args.yaml_file, 'r') as yaml_file:
        data = yaml.safe_load(yaml_file)

    # Find elements by the specified key
    elements_list = list(find_elements_by_key(data, args.key))

    # Output the result as JSON
    print(json.dumps(elements_list, indent=4))

if __name__ == '__main__':
    main()
