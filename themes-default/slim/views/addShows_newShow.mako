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
<script type="text/javascript" src="js/blackwhite.js?${sbPID}"></script>
<script src="js/lib/frisbee.min.js"></script>
<script src="js/lib/vue-frisbee.min.js"></script>
<script src="js/vue-submit-form.js"></script>
<script>
window.app = {};
const startVue = () => {
    window.app = new Vue({
        el: '#vue-wrap',
        metaInfo: {
            title: 'New Show'
        },
        data() {
            return {
                // @TODO: Fix Python conversions
                mounted: false,
                formwizard: null,
                skipShow: '',
                otherShows: ${json.dumps(other_shows)},

                // Show Search
                indexerTimeout: ${app.INDEXER_TIMEOUT},
                searchRequestXhr: null,
                searchStatus: '',
                searchResults: {},
                <% valid_indexers = { str(i): { 'name': v['name'], 'showUrl': v['show_url'], 'icon': v['icon'] } for i, v in iteritems(indexerConfig) } %>
                indexers: ${json.dumps(valid_indexers)},
                validLanguages: ${json.dumps(indexerApi().config['valid_languages'])},
                nameToSearch: '${default_show_name}',
                indexerId: ${provided_indexer or 0},
                indexerLanguage: '${app.INDEXER_DEFAULT_LANGUAGE}',

                // Provided info
                providedInfo: {
                    use: ${json.dumps(use_provided_info)},
                    indexer: ${json.dumps(provided_indexer_name)},
                    indexerId: ${provided_indexer},
                    seriesId: ${provided_indexer_id},
                    seriesDir: ${json.dumps(provided_show_dir)},
                },

                sanitizedNameCache: {},

                selectedRootDir: '',
                whichSeries: '',
            };
        },
        mounted() {
            this.mounted = true;

            if (this.$refs.nameToSearch) {
                this.$refs.nameToSearch.focus();

                if (this.nameToSearch.length !== 0) {
                    this.searchIndexers();
                }
            }

            /* JQuery Form to Form Wizard- (c) Dynamic Drive (www.dynamicdrive.com)
            *  This notice MUST stay intact for legal use
            *  Visit http://www.dynamicdrive.com/ for this script and 100s more. */

            const goToStep = num => {
                $('.step').each((idx, step) => {
                    if ($.data(step, 'section') + 1 === num) {
                        $(step).click();
                    }
                });
            }

            // @TODO: we need to move to real forms instead of this
            const vm = this;
            this.formwizard = new formtowizard({ // eslint-disable-line new-cap, no-undef
                formid: 'addShowForm',
                revealfx: ['slide', 500],
                oninit() {
                    vm.updateBlackWhiteList();
                    if ($('input:hidden[name=whichSeries]').length !== 0 && $('#fullShowPath').length !== 0) {
                        goToStep(3);
                    }
                }
            });

            $(document.body).on('change', 'select[name="quality_preset"]', () => {
                this.$nextTick(() => this.formwizard.loadsection(2));
            });

            $(document.body).on('change', '#anime', () => {
                this.updateBlackWhiteList();
                this.$nextTick(() => this.formwizard.loadsection(2));
            });
        },
        computed: {
            addButtonDisabled() {
                // Currently requires jQuery
                if ($ === undefined || !this.mounted) return true;

                const { whichSeries, selectedRootDir } = this;
                const hiddenWhichSeries = 'input:hidden[name=whichSeries]';
                // @TODO: Simplify
                const isEnabled = (
                    // Root Dir selected or provided
                    (selectedRootDir.length !== 0 ||
                    ($('#fullShowPath').length !== 0 && $('#fullShowPath').val().length !== 0)) && // eslint-disable-line no-mixed-operators
                    // Series selected or provided
                    whichSeries.length !== 0 || // eslint-disable-line no-mixed-operators
                    ($(hiddenWhichSeries).length !== 0 && $(hiddenWhichSeries).val().length !== 0)
                )
                return !isEnabled;
            },
            showName() {
                const { whichSeries } = this;

                // Currently requires jQuery
                if ($ === undefined || !this.mounted) return;

                // If they've picked a radio button then use that
                if (whichSeries.length !== 0) {
                    return whichSeries.split('|')[4];
                // If we provided a show in the hidden field, use that
                } else if ($('input:hidden[name=whichSeries]').length !== 0 && $('input:hidden[name=whichSeries]').val().length !== 0) {
                    return $('#providedName').val();
                } else {
                    return '';
                }
            },
        },
        asyncComputed: {
            async showPath() {
                const { whichSeries, selectedRootDir } = this;
                const { showName } = this;

                // Currently requires jQuery
                if ($ === undefined || !this.mounted) return;

                let showPath;
                let sepChar;
                // If we have a root dir selected, figure out the path
                if (selectedRootDir.length !== 0) {
                    let rootDirectoryText = selectedRootDir;
                    if (rootDirectoryText.indexOf('/') >= 0) {
                        sepChar = '/';
                    } else if (rootDirectoryText.indexOf('\\') >= 0) {
                        sepChar = '\\';
                    } else {
                        sepChar = '';
                    }

                    if (rootDirectoryText.substr(rootDirectoryText.length - 1) !== sepChar) {
                        rootDirectoryText += sepChar;
                    }
                    rootDirectoryText += '<i>||</i>' + sepChar;

                    showPath = rootDirectoryText;
                } else if ($('#fullShowPath').length !== 0 && $('#fullShowPath').val().length !== 0) {
                    showPath = $('#fullShowPath').val();
                } else {
                    return 'unknown dir';
                }

                // If we have a show name then sanitize and use it for the dir name
                if (showName.length > 0) {
                    let sanitizedName = this.sanitizedNameCache[showName];
                    if (sanitizedName === undefined) {
                        const params = {
                            name: showName
                        };
                        const { data } = await api.get('internal/sanitizeFileName', { params });
                        sanitizedName = data.sanitized;
                        this.sanitizedNameCache[showName] = sanitizedName;
                    }
                    return showPath.replace('||', this.sanitizedNameCache[showName]);
                // If not then it's unknown
                } else {
                    return showPath.replace('||', '??');
                }
            }
        },
        methods: {
            vueSubmitForm,
            submitForm() {
                // If they haven't picked a show or a root dir don't let them submit
                if (this.addButtonDisabled) {
                    this.$snotify.warning('You must choose a show and a parent folder to continue.');
                    return;
                }
                generateBlackWhiteList(); // eslint-disable-line no-undef
                return this.vueSubmitForm('addShowForm');
            },
            submitFormSkip() {
                this.skipShow = '1';
                return this.vueSubmitForm('addShowForm');
            },
            rootDirsUpdated(rootDirs) {
                this.selectedRootDir = rootDirs.length === 0 ? '' : rootDirs.find(rd => rd.selected).path;
            },
            searchIndexers() {
                let { nameToSearch, providedInfo, indexerTimeout, indexerLanguage, indexerId } = this;

                if (nameToSearch.length === 0) {
                    return;
                }

                if (this.searchRequestXhr) {
                    this.searchRequestXhr.abort();
                }

                this.whichSeries = '';
                this.searchResults = {};

                const searchingFor = '<b>' + nameToSearch + '</b> on ' + $('#providedIndexer option:selected').text() + ' in ' + indexerLanguage;
                this.searchStatus = '<img id="searchingAnim" src="images/loading32' + MEDUSA.config.themeSpinner + '.gif" height="32" width="32" /> searching ' + searchingFor + '...';

                this.$nextTick(() => this.formwizard.loadsection(0)); // eslint-disable-line no-use-before-define

                this.searchRequestXhr = $.ajax({
                    url: 'addShows/searchIndexersForShowName',
                    data: {
                        search_term: nameToSearch, // eslint-disable-line camelcase
                        lang: indexerLanguage,
                        indexer: indexerId
                    },
                    timeout: indexerTimeout * 1000,
                    dataType: 'json',
                    error() {
                        this.searchStatus = 'search timed out, try again or try another indexer';
                    }
                }).done(data => {
                    this.searchStatus = '';

                    const language = data.langid;
                    const results = data.results
                        .map(result => {
                            // Unpack result items 0 through 6 (Array)
                            let [ indexerName, indexerId, indexerShowUrl, seriesId, seriesName, premiereDate, network ] = result;

                            // Compute whichSeries value:
                            // FIXME: Do we still need this value replace? .replace(/"/g, '')
                            whichSeries = result.join('|')

                            // Append seriesId to indexer show url
                            indexerShowUrl += seriesId;
                            // For now only add the language id to the tvdb url, as the others might have different routes.
                            if (language && language !== '' && indexerId === 1) {
                                indexerShowUrl += '&lid=' + language
                            }

                            // Discard 'N/A' and '1900-01-01'
                            /*
                            const filter = string => ['N/A', '1900-01-01'].includes(string) ? '' : string;
                            premiereDate = filter(premiereDate);
                            network = filter(network);
                            */

                            indexerIcon = 'images/' + this.indexerNameToConfig(indexerName).icon;

                            return {
                                whichSeries,
                                indexerName,
                                indexerId,
                                indexerShowUrl,
                                indexerIcon,
                                seriesId,
                                seriesName,
                                premiereDate,
                                network
                            };
                        });

                    this.searchResults = {
                        language,
                        results
                    };

                    if (results.length !== 0) {
                        // Select the first result
                        this.whichSeries = results[0].whichSeries;
                    }

                    this.$nextTick(() => {
                        this.formwizard.loadsection(0); // eslint-disable-line no-use-before-define
                    });
                });
            },
            <%doc>
            // OLD STYLE
            debutText(result) {
                if (result.premiereDate === null) return '';
                const startDate = new Date(result.premiereDate);
                const today = new Date();
                const prefix = startDate > today ? 'will debut' : 'started';
                return ' (' + prefix + ' on ' + result.premiereDate + ' on ' + result.network + ')';
            },
            </%doc>
            updateBlackWhiteList() {
                // Currently requires jQuery
                if ($ === undefined || !this.mounted) return;
                $.updateBlackWhiteList(this.showName);
            },
            indexerNameToConfig(name) {
                const { indexers } = this;
                const indexerId = Object.keys(indexers)
                    .find(id => indexers[id].name.toLowerCase() === name.toLowerCase());

                if (indexerId === undefined)
                    return {};

                return indexers[indexerId];
            }
        }
    });
};
</script>
</%block>
<%block name="content">
<vue-snotify></vue-snotify>
<h1 class="header">New Show</h1>
<div class="newShowPortal">
    <div id="config-components">
        <ul><li><app-link href="#core-component-group1">Add New Show</app-link></li></ul>
        <div id="core-component-group1" class="tab-pane active component-group">
            <div id="displayText">Adding show <b v-html="showName"></b> into <b v-html="showPath"></b></div>
            <br>
            <form id="addShowForm" method="post" action="addShows/addNewShow" redirect="/home" accept-charset="utf-8">
                <fieldset class="sectionwrap">
                    <legend class="legendStep">Find a show on selected indexer(s)</legend>
                    <div v-if="providedInfo.use" class="stepDiv">
                        Show retrieved from existing metadata: <app-link :href="indexers[providedInfo.indexerId].showUrl + providedInfo.seriesId">{{ providedInfo.indexer }}</app-link>
                        <input type="hidden" id="indexer_lang" name="indexer_lang" value="en" />
                        <input type="hidden" id="whichSeries" name="whichSeries" :value="providedInfo.seriesId" />
                        <input type="hidden" id="providedIndexer" name="providedIndexer" :value="providedInfo.indexerId" />
                        <input type="hidden" id="providedName" :value="providedInfo.indexer" />
                    </div>
                    <div v-else class="stepDiv">
                        <input type="text" v-model.trim="nameToSearch" ref="nameToSearch" @keyup.enter="searchIndexers" class="form-control form-control-inline input-sm input350"/>
                        &nbsp;&nbsp;
                        <language-select @update-language="indexerLanguage = $event" name="indexer_lang" id="indexerLangSelect" :language="indexerLanguage" :available="validLanguages.join(',')" class="form-control form-control-inline input-sm"></language-select>
                        <b>*</b>
                        &nbsp;
                        <select name="providedIndexer" id="providedIndexer" v-model="indexerId" class="form-control form-control-inline input-sm">
                            <option :value.number="0">All Indexers</option>
                            <option v-for="(indexer, indexerId) in indexers" :value.number="indexerId">{{indexer.name}}</option>
                        </select>
                        &nbsp;
                        <input class="btn-medusa btn-inline" type="button" id="searchName" value="Search" @click="searchIndexers" />

                        <p style="padding: 20px 0;">
                            <b>*</b> This will only affect the language of the retrieved metadata file contents and episode filenames.<br />
                            This <b>DOES NOT</b> allow Medusa to download non-english TV episodes!
                        </p>

                        <div v-if="searchResults.results === undefined" v-html="searchStatus"></div>
                        <div v-else class="search-results">
                            <legend class="legendStep">Search Results:</legend>
                            <table v-if="searchResults.results.length !== 0" class="search-results">
                                <thead>
                                    <tr>
                                        <th></th>
                                        <th>Show Name</th>
                                        <th class="premiere">Premiere</th>
                                        <th class="network">Network</th>
                                        <th class="indexer">Indexer</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <tr v-for="result in searchResults.results" @click="whichSeries = result.whichSeries" :class="{ selected: whichSeries === result.whichSeries }">
                                        <td style="text-align: center; vertical-align: middle;">
                                            <input v-model="whichSeries" type="radio" :value="result.whichSeries" id="whichSeries" name="whichSeries" />
                                        </td>
                                        <td>
                                            <app-link :href="result.indexerShowUrl" title="Go to the show's page on the indexer site">
                                                <b>{{ result.seriesName }}</b>
                                            </app-link>
                                        </td>
                                        ## <td class="premiere">{{ result.premiereDate }}</td>
                                        ## <td class="network">{{ result.network }}</td>
                                        <td class="premiere">{{ !['N/A', '1900-01-01'].includes(result.premiereDate) ? result.premiereDate : '' }}</td>
                                        <td class="network">{{ result.network !== 'N/A' ? result.network : '' }}</td>
                                        <td class="indexer">
                                            {{ result.indexerName }}
                                            <img height="16" width="16" :src="result.indexerIcon" />
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            <div v-else class="no-results">
                                <b>No results found, try a different search.</b>
                            </div>
                        </div>

                        <%doc>
                        ## OLD STYLE
                        <div id="searchResults" style="height: 100%;">
                            <div v-if="searchResults.results === undefined" class="search-status" v-html="searchStatus"></div>
                            <fieldset v-else>
                                <legend class="legendStep">Search Results:</legend>
                                <b v-if="searchResults.results.length === 0">No results found, try a different search.</b>
                                <div v-else v-for="result in searchResults.results">
                                    <input v-model="whichSeries" type="radio" :value="result.whichSeries" id="whichSeries" name="whichSeries" style="vertical-align: -2px;" />
                                    <app-link :href="result.indexerShowUrl">
                                        <b>{{ result.seriesName }}</b>
                                    </app-link>

                                    <span v-if="result.premiereDate !== null" v-html="debutText(result)"></span>
                                    <span v-if="result.indexerName !== null"> [{{result.indexerName}}]</span>
                                </div>
                            </fieldset>
                        </div>
                        </%doc>
                    </div>
                </fieldset>
                <fieldset class="sectionwrap">
                    <legend class="legendStep">Pick the parent folder</legend>
                    <div v-if="providedInfo.seriesDir" class="stepDiv">
                        Pre-chosen Destination Folder: <b>{{providedInfo.seriesDir}}</b> <br>
                        <input type="hidden" id="fullShowPath" name="fullShowPath" :value="providedInfo.seriesDir" /><br>
                    </div>
                    <div v-else class="stepDiv">
                        <root-dirs @update:root-dirs="rootDirsUpdated"></root-dirs>
                    </div>
                </fieldset>
                <fieldset class="sectionwrap">
                    <legend class="legendStep">Customize options</legend>
                    <div class="stepDiv">
                        <%include file="/inc_addShowOptions.mako"/>
                    </div>
                </fieldset>

                <input v-for="curNextDir in otherShows" type="hidden" name="other_shows" :value="curNextDir" />

                <input type="hidden" name="skipShow" id="skipShow" :value="skipShow" />
            </form>
            <br>
            <div style="width: 100%; text-align: center;">
                <input @click.prevent="submitForm" id="addShowButton" class="btn-medusa" type="button" value="Add Show" :disabled="addButtonDisabled" />
                <input v-if="providedInfo.seriesDir" @click.prevent="submitFormSkip" class="btn-medusa" type="button" id="skipShowButton" value="Skip Show" />
            </div>
        </div>
    </div>
</div>
</%block>
