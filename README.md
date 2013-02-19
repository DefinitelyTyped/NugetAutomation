NugetAutomation
==============================

This project contains the automation used to generate NuGet packages for each of the TypeScript definitions in the DefinetlyTyped project.


How to generate the packages
============================

From a PowerShell prompt:

    git clone https://github.com/DefinitelyTyped/NugetAutomation.git
    ./CreatePackages.ps1

And it should generate packages in the `./build` folder.



