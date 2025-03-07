# End-2-End Tests

## Adding a new End-2-End Test :

If your test code is inside the sample app directory, you can create a symbolic link :

```sh
ln -s ../../sample_apps/{your_sample_app}/test {your_sample_app}
```

Which is already used to perform the following end-2-end tests :
- `rails7.1_sql_injection`
- `rails7.1_path_traversal`
