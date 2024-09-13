Initially I tried to nest yaml with just yq using:
```
yq eval '{"artifactory": .}' artifactory-large.yaml > nested-artifactory-large.yaml

yq eval '{"artifactory": .}' artifactory-large-extra-config.yaml >  nested-artifactory-large-extra-config.yaml
```
Then merge using:

```
yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1) * select(fileIndex == 2)' values-main.yaml nested-artifactory-large.yaml nested-artifactory-large-extra-config.yaml > merged-values.yaml
```

or
Merge with best effort to preserve comments, formatting,
and order of items from https://github.com/Aref-Riant/yaml-merger-py


```
pip install ruamel.yaml
pip install mergedeep
python yaml-merger.py values-main.yaml nested-artifactory-large.yaml nested-artifactory-large-extra-config.yaml > merged-values.yaml
```

or
Merge multiple YAML files, ignoring commented lines and preserving the intended configuration using:
```
python merge_yaml.py nested-artifactory-large.yaml nested-artifactory-large-extra-config.yaml -o merged-values.yaml
```
or
```
https://github.com/wwkimball/yamlpath
pip install yamlpath
yaml-merge nested-artifactory-large.yaml nested-artifactory-large-extra-config.yaml
```

But all the above was messing up with the formatting of the `artifactory.artifactory.javaOpts.other`.

Finally came up with following for nesting the entire yaml under a key like `artifactory` while retaining all the comments:
[nest_yaml_with_comments.py](nest_yaml_with_comments.py)
[merge_yaml_with_comments.py](merge_yaml_with_comments.py)
```
pip install ruamel.yaml
python nest_yaml_with_comments.py artifactory-large.yaml artifactory -o nested-artifactory-large.yaml 
python nest_yaml_with_comments.py artifactory-large-extra-config.yaml artifactory -o nested-artifactory-large-extra-config.yaml 
```
Then merge them using:
```
python merge_yaml_with_comments.py values-main.yaml nested-artifactory-large.yaml nested-artifactory-large-extra-config.yaml -o merged-values1.yaml
```
Note: With `nest_yaml_with_comments.py` you can also nest deep ( under key `artifactory.xyz` ) , for example:
```
python nest_yaml_with_comments.py artifactory-large-extra-config.yaml artifactory.xyz -o nested-artifactory-large-extra-config.yaml 

If any nested key has space character then you can use double quotes :
python nest_yaml_with_comments.py artifactory-large-extra-config.yaml artifactory."hello xyz" -o nested-artifactory-large-extra-config.yaml 
```
Note: if any key has all the sub keys commente then dont use the key in merging the yamls with any of the merge options above
as it will set the child key values to  null.
For example merging 1 yaml  with:
```
    database:
      maxOpenConnections: 200 
```
to the next yaml specified on the right which has at least one child key :
```
    database:
    #   maxOpenConnections: 100
      xyz: 20
```
will result in the expected yaml  :
```
    database:
      maxOpenConnections: 200
      xyz: 20
```
But if you try to merge it with:
```
    database:
    #   maxOpenConnections: 100
```
will result in the unexpected  in the final merged yaml file:
```
    database:
```
To avoid this do not specify the `database` key in the next yaml file so that you get the expected:
```
    database:
      maxOpenConnections: 200 
```