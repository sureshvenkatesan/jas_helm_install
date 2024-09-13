# https://stackoverflow.com/questions/9680863/nested-dictionaries-extracting-paths-to-leaves
# https://stackoverflow.com/questions/7255885/save-dump-a-yaml-file-with-comments-in-pyyaml


#import yaml
import sys
import ruamel.yaml
from mergedeep import merge

## Show help
if len(sys.argv) < 2:
    print("Usage: python yaml-merger.py file1.yaml file2.yaml > mergedfile.yaml")
    quit()

## Define class to represent null values as u'null'
def represent_none(self, _):
    return self.represent_scalar('tag:yaml.org,2002:null', u'null')

## Define class to represent null values as ''
#def represent_none(self, _):
#    return self.represent_scalar('tag:yaml.org,2002:null', '')

yaml = ruamel.yaml.YAML()

# Set the representer class
yaml.representer.add_representer(type(None), represent_none)

# Set indent config
yaml.indent(mapping=2, sequence=4, offset=2)

# Set to presernve qoutes as in original file
yaml.preserve_quotes=True

# Load file1
f = open(sys.argv[1], "r")
code = yaml.load(f)

# Load file2
f2 = open(sys.argv[2], "r")
code2 = yaml.load(f2)


## Functions to get leaves of nested dict
from collections.abc import Mapping

def isDict(d):
    return isinstance(d, Mapping)

def isAtomOrFlat(d):
    return not isDict(d) or not any(isDict(v) for v in d.values())

def leafPaths(nestedDicts, noDeeper=isAtomOrFlat):
    for key,value in nestedDicts.items():
        if noDeeper(value):
            yield {key: value}
        else:
            for subpath in leafPaths(value):
                yield {key: subpath}

leaves=list(leafPaths(code2))
##

## Use this method of you need to apply filters on leaves individually
#for l in leaves:
#  # filters and rules
#  merge(code, l)


## Use this if you want simple merge without any filter
merge(code,code2)

## Dump merged yaml into stdout (use '>' or '|tee' to write into file)
yaml.dump(code, sys.stdout)

