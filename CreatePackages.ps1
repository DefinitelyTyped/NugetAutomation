
# https://github.com/borisyankov/DefinitelyTyped.git

$nuget = (get-item ".\tools\NuGet.CommandLine.2.2.1\tools\NuGet.exe")
$packageIdFormat = "{0}.TypeScript.DefinetlyTyped"
$nuspecTemplate = get-item ".\PackageTemplate.nuspec"

function Get-MostRecentNugetSpec($nugetPackageId) {
    $feeedUrl= "http://packages.nuget.org/v1/FeedService.svc/Packages()?`$filter=Id%20eq%20'$nugetPackageId'&`$orderby=Version%20desc&`$top=1"
    $webClient = new-object System.Net.WebClient
    $feedResults = [xml]($webClient.DownloadString($feeedUrl))
    return $feedResults.feed.entry
}

function Get-Last-NuGet-Version($spec) {
    $spec.properties.version
}

function Create-Directory($name){
	if(!(test-path $name)){
		mkdir $name | out-null
		write-host "Created Dir: $name"
	}
}

function Get-PackageSha256($filePath) {
    $file = [System.IO.File]::Open($filePath, "open", "read")
    $hashBytes = [System.Security.Cryptography.SHA512Managed]::Create().ComputeHash($file)
    [System.Convert]::ToBase64String($hashBytes);
    $file.Dispose()
}


function Increment-Version($version){

	if(!$version) {
		return "0.0.1";
	}

    $parts = $version.split('.')
    for($i = $parts.length-1; $i -ge 0; $i--){
        $x = ([int]$parts[$i]) + 1
        if($i -ne 0) {
            # Don't roll the previous minor or ref past 10
            if($x -eq 10) {
                $parts[$i] = "0"
                continue
            }
        }
        $parts[$i] = $x.ToString()
        break;
    }
    [System.String]::Join(".", $parts)
}


function Create-Package() {
    BEGIN {
    }
    PROCESS {
		$dir = $_
		$packageName = $dir.Name
		$packageId = $packageIdFormat -f $packageName

		$tsFiles = ls $dir -recurse -include *.d.ts

		if( $tsFiles ) {

            $mostRecentNuspec = (Get-MostRecentNugetSpec $packageId)

			$currentVersion = $mostRecentNuspec.properties.version
			$newVersion = Increment-Version $currentVersion
			$packageFolder = "$packageId.$newVersion"
			
			# Create the directory structure
			$deployDir = "$packageFolder\Content\Scripts\typings\$packageName"
			Create-Directory $deployDir
			$tsFiles | %{ cp $_ $deployDir}
			
			# setup the nuspec file
			$currSpecFile = "$packageFolder\$packageId.nuspec"
			cp $nuspecTemplate $currSpecFile
			$nuspec = [xml](cat $currSpecFile)
			$nuspec.package.metadata.id = $packageId
			$nuspec.package.metadata.version = $newVersion
			$nuspec.package.metadata.tags = "TypeScript JavaScript $pakageName"
			$nuspec.package.metadata.description = "TypeScript Definitions (d.ts) for {0} generated from the DefinetlyTyped github repository" -f $packageName
			$nuspec.Save((get-item $currSpecFile))

			& $nuget pack $currSpecFile

            # make sure the hash algo hasn't changed on us.
            if($mostRecentNuspec.properties.PackageHashAlgorithm -ne $null -and $mostRecentNuspec.properties.PackageHashAlgorithm -ne "SHA512") {
                throw "package with id $packageId contains a PackageHashAlgorithm[$($mostRecentNuspec.properties.PackageHashAlgorithm)] that is not SHA512"
            }

            $packageCreated = get-item "$packageFolder.nupkg"
            $newPackageSha = Get-PackageSha256 $packageCreated
            if($newPackageSha -ne $mostRecentNuspec.properties.PackageHash) {
                # TODO: the packages are different - look to uploade a new one...
            }
		}
    }
    END {
	}
}

# make sure the submodule is here and up to date.
git submodule init
git submodule update
git submodule foreach git pull origin master

$packageDirectories = ls .\Definitions\* -Directory

rm build -recurse -force -ErrorAction SilentlyContinue
Create-Directory build

try {
	pushd build

# for testing purposed - limits the number of packages created
#	$packageDirectories | select -first 5 | create-package
	$packageDirectories | create-package
	
	popd
}
catch {
	popd
	write-error $_
}