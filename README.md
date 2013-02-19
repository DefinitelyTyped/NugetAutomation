DefinetlyTyped.NugetAutomation
==============================

Automatically generate nuget packages for the DefinetlyTyped TypeScript definitions.


How to generate the packages
============================

From a PowerShell prompt:

    git clone https://github.com/staxmanade/DefinetlyTyped.NugetAutomation.git
    git submodule init
    git submodule update
    ./CreatePackages.ps1

And it should generate packages in the `./build` folder.



