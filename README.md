NugetAutomation
==============================

# ********* UPDATE *********

> This project is now officially pretty much over... Since the conversion to type defs 2.0 where all types are in [npm](https://npmjs.com) nuget packages are no longer being published or supported...



This project contains the automation used to generate [NuGet](http://www.nuget.org/profiles/DefinitelyTyped) packages for each of the TypeScript definitions in the [DefinitelyTyped](https://github.com/borisyankov/DefinitelyTyped)  project.

It's not really intended to be used by anyone, however if you'd like to see how we automate this process, or have feedback on how it is working please open an issue or send a pull request!

AppVeyor
========

We have AppVeyor configured to run every 2 hours. Any and all changes to the DT project get published to NuGet.


Usages
======

This is how the script can be used to generate a dry-run. Generating nuget packages, but not applying any side-effects (publishing to nuget, committing to the git repo, pushing the code up to github).

    .\CreatePackages.ps1

We can also use the script to generate specific package.

    .\CreatePackages.ps1 -specificPackages angularjs
    .\CreatePackages.ps1 -specificPackages @('angularjs', 'backbone')


The following is how we run the script for a full on [double rainbow](http://www.youtube.com/watch?v=OQSNhk5ICTI) packages creation.

    .\CreatePackages.ps1 -nugetApiKey <this is a secret - no-no>  -CommitLocalGit -PushGit -PublishNuget


And there should be a folder `./build` where any nuget packages generated will reside.


How to re-publish ALL packages?
===============================

The happy path should be this doesn't need to happen. An example that may cause this to not be so happy is if links in the project change and the nuspec template has to be updated for all packages.

To re-publish all packages:

- First delete the `LAST_PUBLISHED_COMMIT` file
- Then run the CreatePackages (as described above) with the necessary arguments.
