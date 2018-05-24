<%inherit file="/layouts/main.mako"/>
<%!
    import json

    from medusa import app
    from medusa.indexers.indexer_api import indexerApi
    from medusa.indexers.indexer_config import indexerConfig

    from six import iteritems, text_type as str
%>
<%block name="scripts">
<script type="text/javascript" src="js/add-show-options.js?${sbPID}"></script>
<script>
window.app = {};
const startVue = () => {
    window.app = new Vue({
        el: '#vue-wrap',
        metaInfo: {
            title: 'Existing Show'
        },
        data() {
            <% indexers = { str(i): { 'name': v['name'], 'showUrl': v['show_url'] } for i, v in iteritems(indexerConfig) } %>
            return {
                // @FIXME: Python conversions (fix when config is loaded before routes)
                indexers: ${json.dumps(indexers)},
                defaultIndexer: ${app.INDEXER_DEFAULT},

                isLoading: false,
                rootDirs: [],
                dirList: [],
                promptForSettings: false
            };
        },
        mounted() {
            // Need to delay that a bit
            this.$nextTick(() => {
                // Hide the black/whitelist, because it can only be used for a single anime show
                $.updateBlackWhiteList(undefined);
            });
        },
        computed: {
            selectedRootDirs() {
                return this.rootDirs.filter(rd => rd.selected);
            },
            filteredDirList() {
                return this.dirList.filter(dir => !dir.alreadyAdded);
            },
            displayPaths() {
                // Mark the root dir as bold in the path
                return this.filteredDirList
                    .map(dir => {
                        const rootDir = this.rootDirs.find(rd => dir.path.startsWith(rd.path)).path;
                        const pathSep = rootDir.indexOf('\\') > -1 ? 2 : 1;
                        const rdEndIndex = dir.path.indexOf(rootDir) + rootDir.length + pathSep;
                        return '<b>' + dir.path.slice(0, rdEndIndex) + '</b>' + dir.path.slice(rdEndIndex);
                    });
            },
            checkAll: {
                get() {
                    const selectedDirList = this.filteredDirList.filter(dir => dir.selected);
                    if (selectedDirList.length === 0) return false;
                    return selectedDirList.length === this.filteredDirList.length;
                },
                set(newValue) {
                    this.dirList = this.dirList.map(dir => {
                        dir.selected = newValue;
                        return dir;
                    });
                }
            }
        },
        methods: {
            rootDirsUpdated(value, data) {
                this.rootDirs = data.map(rd => {
                    return {
                        selected: true,
                        path: rd.path
                    };
                });
            },
            async update() {
                if (this.isLoading) return;

                this.isLoading = true;

                const indices = this.rootDirs
                    .reduce((indices, rd, idx) => {
                        if (rd.selected) indices.push(idx);
                        return indices;
                    }, []);
                if (indices.length === 0) {
                    this.dirList = [];
                    this.isLoading = false;
                    return;
                }

                const params = { 'root-dirs': indices.join(',') };
                const { data } = await api.get('internal/existingSeries', { params });
                this.dirList = data
                    .map(dir => {
                        // Pre-select all dirs not already added
                        dir.selected = !dir.alreadyAdded;
                        dir.selectedIndexer = dir.metadata.indexer || this.defaultIndexer;
                        return dir;
                    });
                this.isLoading = false;

                this.$nextTick(() => {
                    $('#addRootDirTable')
                        .tablesorter({
                            widgets: ['zebra'],
                            // This fixes the checkAll checkbox getting unbound because this code changes the innerHTML of the <th>
                            // https://github.com/Mottie/tablesorter/blob/v2.28.1/js/jquery.tablesorter.js#L566
                            headerTemplate: '',
                            headers: {
                                0: { sorter: false },
                                3: { sorter: false }
                            }
                        })
                        // Fixes tablesorter not working after root dirs are refreshed
                        .trigger("updateAll");
                });
            },
            seriesIndexerUrl(curDir) {
                return this.indexers[curDir.metadata.indexer].showUrl + curDir.metadata.seriesId.toString();
            },
            submitSeriesDirs() {
                const dirArr = this.filteredDirList
                    .reduce((accumlator, dir) => {
                        if (!dir.selected) return accumlator;

                        const originalIndexer = dir.metadata.indexer;
                        let seriesId = dir.metadata.seriesId;
                        if (originalIndexer !== null && originalIndexer !== dir.selectedIndexer) {
                            seriesId = '';
                        }

                        const seriesToAdd = [dir.selectedIndexer, dir.path, seriesId, dir.metadata.seriesName]
                            .filter(i => typeof(i) === 'number' || Boolean(i)).join('|');
                        accumlator.push(encodeURIComponent(seriesToAdd));
                        return accumlator;
                    }, []);

                if (dirArr.length === 0) return false;

                const promptForSettings = 'promptForSettings=' + (this.promptForSettings ? 'on' : 'off');
                const seriesToAdd = 'shows_to_add=' + dirArr.join('&shows_to_add=');
                window.location.href = $('base').attr('href') + 'addShows/addExistingShows?' + promptForSettings + '&' + seriesToAdd;
            }
        },
        watch: {
            selectedRootDirs() {
                this.update();
            }
        }
    });
};
</script>
</%block>
<%block name="content">
<h1 class="header">Existing Show</h1>
<div class="newShowPortal">
    <div id="config-components">
        <ul><li><app-link href="#core-component-group1">Add Existing Show</app-link></li></ul>
        <div id="core-component-group1" class="tab-pane active component-group">
            <form id="addShowForm" method="post" action="addShows/addExistingShows" accept-charset="utf-8">
                <div id="tabs">
                    <ul>
                        <li><app-link href="addShows/existingShows/#tabs-1">Manage Directories</app-link></li>
                        <li><app-link href="addShows/existingShows/#tabs-2">Customize Options</app-link></li>
                    </ul>
                    <div id="tabs-1" class="existingtabs">
                        <root-dirs @update:root-dirs-value="rootDirsUpdated"></root-dirs>
                    </div>
                    <div id="tabs-2" class="existingtabs">
                        <%include file="/inc_addShowOptions.mako"/>
                    </div>
                </div>
                <br>
                <p>Medusa can add existing shows, using the current options, by using locally stored NFO/XML metadata to eliminate user interaction.
                If you would rather have Medusa prompt you to customize each show, then use the checkbox below.</p>
                <p><input type="checkbox" v-model="promptForSettings" id="promptForSettings" /> <label for="promptForSettings">Prompt me to set settings for each show</label></p>
                <hr>
                <p><b>Displaying folders within these directories which aren't already added to Medusa:</b></p>
                <ul id="rootDirStaticList">
                    <li v-for="(rootDir, idx) in rootDirs" class="ui-state-default ui-corner-all" @click="rootDirs[idx].selected = !rootDirs[idx].selected">
                        <input type="checkbox" class="rootDirCheck" v-model="rootDir.selected" :value="rootDir.path" style="cursor: pointer;">
                        <label><b style="cursor: pointer;">{{rootDir.path}}</b></label>
                    </li>
                </ul>
                <br>
                <span v-if="isLoading"><img id="searchingAnim" src="images/loading32.gif" height="32" width="32" /> loading folders...</span>
                <span v-if="!isLoading && Object.keys(dirList).length === 0">No folders selected.</span>
                <table v-show="!isLoading && Object.keys(dirList).length !== 0" id="addRootDirTable" class="defaultTable tablesorter">
                    <thead>
                        <tr>
                            <th class="col-checkbox"><input type="checkbox" v-model="checkAll" /></th>
                            <th>Directory</th>
                            <th width="20%">Show Name (tvshow.nfo)</th>
                            <th width="20%">Indexer</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr v-for="(curDir, curDirIndex) in filteredDirList">
                            <td class="col-checkbox">
                                <input type="checkbox" v-model="curDir.selected" :value="curDir.path" class="seriesDirCheck" />
                            </td>
                            <td>
                                <label @click="curDir.selected = !curDir.selected" v-html="displayPaths[curDirIndex]"></label>
                            </td>
                            <td>
                                <app-link v-if="curDir.metadata.seriesName && curDir.metadata.indexer > 0"
                                          :href="seriesIndexerUrl(curDir)">{{curDir.metadata.seriesName}}</app-link>
                                <span v-else>?</span>
                            </td>
                            <td align="center">
                                <select name="indexer" v-model="curDir.selectedIndexer">
                                    <option :value.number="0">All Indexers</option>
                                    <option v-for="(indexer, indexerId) in indexers" :value.number="indexerId">{{indexer.name}}</option>
                                </select>
                            </td>
                        </tr>
                    </tbody>
                </table>
                <br>
                <br>
                <input class="btn-medusa" type="button" value="Submit" :disabled="isLoading" @click="submitSeriesDirs" />
            </form>
        </div>
    </div>
</div>
</%block>
