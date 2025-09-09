# Sample app template

## Installation

To get the app up and running you'll first have to link the gemfiles, do so in the main directory with:

```sh
$ bin/link_gemfile
```

Then it's important to build the `aikido-zen` gem we are going to use inside the sample app, to do so run the following snippet in the main directory:

```sh
$ bundle exec rake build
```

Afterwards, inside the directory of the sample app, run the following code to setup and start the server:

```sh
$ bin/setup
$ bin/rails server
```

## Port

To specify the port you can set the `PORT` environment variable, default is `3000`

## Injection

Open http://localhost:3000 and enter the hostname to resolve:

- `dangerous-hostname`, where `dangerous-hostname` resolves to `169.254.169.254`.
