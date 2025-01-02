# Sample app for Path Traversal

## Installation

To get the app up and running you'll first have to link the gemfiles, do so in the main directory with :
```shell
$ bin/link_gemfile
```

Then it's important to build the `aikido-zen` gem we are going to use inside the sample app, to do so run the following snippet in the main directory :
```shell
$ bundler exec rake build
```

Afterwards, inside the directory of the sample app, run the following code to setup and start the server:
```sh
$ bin/setup
$ bin/rails server
```
## Port

To specify the port you can set the `PORT` environment variable, default is `3000`

## Injection

An example injection: `../../config/routes.rb`, you can execute this on route http://localhost:3000