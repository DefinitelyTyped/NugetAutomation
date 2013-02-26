NugetAutomation
==============================

This project contains the automation used to generate NuGet packages for each of the TypeScript definitions in the DefinetlyTyped project.

It's not really intended to be used by anyone, however if you'd like to see how we automate this process, or have feedback on how it is working please open an issue or send a pull request!



Usages
======

This is how the script can be used to generate a dry-run. Generating nuget packages, but not applying any side-effects (publishing to nuget, commiting to the git repo, pushing the code up to github).

    .\CreatePackages.ps1

We can also use the script to generate specific package.

    .\CreatePackages.ps1 -specificPackages angularjs
    .\CreatePackages.ps1 -specificPackages @('angularjs', 'backbone')


The following is how we run the script for a full on [double rainbow](http://www.youtube.com/watch?v=OQSNhk5ICTI) packages creation.

    .\CreatePackages.ps1 -nugetApiKey <this is a secret - no-no>  -CommitLocalGit -PushGit -PublishNuget


And there should be a folder `./build` where any nuget packages generated will reside.
