/// One-time environment installer for the Agentic MCP adapter.
///
/// Creates a shared database to hold the adapter code and maps it into the %ALL
/// pseudo-namespace, so that every namespace on the instance — present and future —
/// can use the adapter without a per-namespace install.
///
/// Only the CODE is shared. Message data globals are deliberately NOT mapped, so
/// each namespace keeps its own message store and one production cannot see
/// another's traffic.
///
/// Run once, before loading the module:
///     do ##class(Agentic.Install).Setup()
///     zpm "load /path/to/Agentic-Adapter-in-Execution-Time"
///
/// This class is not part of the shared package and does not need to be mapped.
Class Agentic.Install
{

/// Database that holds the shared adapter code.
Parameter DBNAME = "AGENTICLIB";

/// Package mapped to every namespace.
Parameter PACKAGE = "Agentic.Adapter";

/// Create the shared database and map the adapter package into all namespaces.
/// pDirectory defaults to <mgr>/agenticlib.
ClassMethod Setup(pDirectory As %String = "", pDBName As %String = {..#DBNAME}) As %Status
{
    new $namespace
    set $namespace = "%SYS"
    set tSC = $$$OK
    try {
        if pDirectory = "" {
            set pDirectory = ##class(%File).NormalizeDirectory($system.Util.ManagerDirectory()_$zconvert(pDBName, "L"))
        }

        ; 1. database
        if ##class(Config.Databases).Exists(pDBName) {
            write "database ", pDBName, " already exists", !
        } else {
            if '##class(%File).DirectoryExists(pDirectory) {
                if '##class(%File).CreateDirectoryChain(pDirectory) {
                    set tSC = $$$ERROR($$$GeneralError, "could not create "_pDirectory)
                    quit
                }
            }
            if '##class(%File).Exists(pDirectory_"IRIS.DAT") {
                set tSC = ##class(SYS.Database).CreateDatabase(pDirectory)
                if $$$ISERR(tSC) quit
            }
            set tProps("Directory") = pDirectory
            set tSC = ##class(Config.Databases).Create(pDBName, .tProps)
            if $$$ISERR(tSC) quit
            write "created database ", pDBName, " at ", pDirectory, !
        }

        ; 2. the %ALL pseudo-namespace, which holds mappings applied to every
        ;    namespace. It does not exist on a stock instance and must be created
        ;    before anything can be mapped into it. Its own databases are not used.
        if '##class(Config.Namespaces).Exists("%ALL") {
            set tNs("Globals") = "IRISSYS"
            set tNs("Routines") = "IRISSYS"
            set tSC = ##class(Config.Namespaces).Create("%ALL", .tNs)
            if $$$ISERR(tSC) quit
            write "created %ALL pseudo-namespace", !
        }

        ; 3. package mapping in %ALL - class definitions
        set tSC = ..mapPackage(pDBName, ..#PACKAGE)
        if $$$ISERR(tSC) quit

        ; 4. routine mapping in %ALL - the code generated from those classes
        set tSC = ..mapRoutines(pDBName, ..#PACKAGE_".*")
        if $$$ISERR(tSC) quit

        write "mapped ", ..#PACKAGE, " to ", pDBName, " in %ALL", !
        write "now load the module in any namespace: zpm ""load <path>""", !
    }
    catch ex {
        set tSC = ex.AsStatus()
    }
    quit tSC
}

/// Map a package into %ALL, replacing any existing mapping.
ClassMethod mapPackage(pDBName As %String, pPackage As %String) As %Status [ Internal ]
{
    set tProps("Database") = pDBName
    if ##class(Config.MapPackages).Exists("%ALL", pPackage) {
        quit ##class(Config.MapPackages).Modify("%ALL", pPackage, .tProps)
    }
    quit ##class(Config.MapPackages).Create("%ALL", pPackage, .tProps)
}

/// Map a routine pattern into %ALL, replacing any existing mapping.
ClassMethod mapRoutines(pDBName As %String, pPattern As %String) As %Status [ Internal ]
{
    set tProps("Database") = pDBName
    if ##class(Config.MapRoutines).Exists("%ALL", pPattern) {
        quit ##class(Config.MapRoutines).Modify("%ALL", pPattern, .tProps)
    }
    quit ##class(Config.MapRoutines).Create("%ALL", pPattern, .tProps)
}

/// Remove the mappings. The database and its contents are left alone.
ClassMethod Unmap() As %Status
{
    new $namespace
    set $namespace = "%SYS"
    if ##class(Config.MapPackages).Exists("%ALL", ..#PACKAGE) {
        do ##class(Config.MapPackages).Delete("%ALL", ..#PACKAGE)
    }
    if ##class(Config.MapRoutines).Exists("%ALL", ..#PACKAGE_".*") {
        do ##class(Config.MapRoutines).Delete("%ALL", ..#PACKAGE_".*")
    }
    write "mappings removed", !
    quit $$$OK
}

/// Report where the adapter is visible from. Diagnostic.
ClassMethod Verify() As %Status
{
    new $namespace
    set tHere = $namespace
    set tList = ""
    set $namespace = "%SYS"
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Nsp FROM %SYS.Namespace_List()")
    while rs.%Next() { set tList = tList_$listbuild(rs.%Get("Nsp")) }
    for i = 1:1:$listlength(tList) {
        set tNs = $list(tList, i)
        if tNs = "%SYS" continue
        set $namespace = tNs
        write $justify(tNs, 18), " : "
        write $select(##class(%Dictionary.CompiledClass).%ExistsId("Agentic.Adapter.MCP"): "adapter visible", 1: "NOT visible"), !
    }
    set $namespace = tHere
    quit $$$OK
}

}
