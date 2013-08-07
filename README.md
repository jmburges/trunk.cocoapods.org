# trunk.cocoapods.org

Available under the MIT license.

## Installation

1. Configure [PageKite](https://pagekite.net) to forward TravisCI webhooks to your local
   development machine and leave this running.

        $ pagekite.py 4567 [YOUR KITE NAME].pagekite.me

   Replace the `webhooks` value in the `.travis.yml` file with your PageKite address.

   _Alternatives to PageKite, include [localtunnel](http://progrium.com/localtunnel/)._

2. Create a testing sandbox repository on GitHub and, from the CocoaPods specification repository,
   add the [`Gemfile`](https://raw.github.com/CocoaPods/Specs/master/Gemfile),
   [`Rakefile`](https://raw.github.com/CocoaPods/Specs/master/Rakefile),
   and [`.travis.yml`](https://raw.github.com/CocoaPods/Specs/master/.travis.yml) files.

3. Enable TravisCI for the testing sandbox repository.

4. Install PostgreSQL.

5. Install the dependencies:

        $ rake bootstrap

6. Create the PostgreSQL databases for the various environments:

        $ createdb -h localhost trunk_cocoapods_org_test -E UTF8
        $ createdb -h localhost trunk_cocoapods_org_development -E UTF8
        $ createdb -h localhost trunk_cocoapods_org_production -E UTF8

7. Test wether or not a

        $ ./bin/test-push localhost:4567 spec/fixtures/AFNetworking.podspec

## Usage

To start a development server run the following command, replacing the environment variables with
your GitHub credentials, a GitHub testing sandbox repository, your Travis-CI API token, and a SHA
hashed version of the password for the admin area (in this example the password is ‘secret’):

    env GH_USERNAME=alloy GH_PASSWORD=secret GH_REPO=alloy/trunk.cocoapods.org-test TRAVIS_API_TOKEN=secret TRUNK_APP_ADMIN_PASSWORD=2bb80d537b1da3e38bd30361aa855686bde0eacd7162fef6a25fe97bf527a25b rake serve

Optional environment variables are:

* RACK_ENV: Can be test, development, or production.
* DATABASE_URL: The URL to the PostgreSQL database.
