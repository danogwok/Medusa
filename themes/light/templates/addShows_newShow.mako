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
                header: 'New Show',
                mounted: false,

                useFormtowizard: true,
                myform: null, // Formwizard
                skipShow: '',
                otherShows: ${json.dumps(other_shows)},

                // Show Search
                indexerTimeout: ${app.INDEXER_TIMEOUT},
                searchRequestXhr: null,
                searchRequestText: '<br />',
                searchResults: [],
                <% valid_indexers = { str(i): { 'name': v['name'], 'showUrl': v['show_url'] } for i, v in iteritems(indexerConfig) } %>
                indexers: ${json.dumps(valid_indexers)},
                validLanguages: ${json.dumps(indexerApi().config['valid_languages'])},
                nameToSearch: '${default_show_name}',
                indexerId: ${provided_indexer or 0},
                language: '${app.INDEXER_DEFAULT_LANGUAGE}',

                // Provided info
                providedInfo: {
                    indexer: ${json.dumps(provided_indexer_name)},
                    indexerId: ${provided_indexer},
                    seriesId: ${provided_indexer_id},
                    seriesDir: ${json.dumps(provided_show_dir)},
                },

                searchTerm: '',
                searchLang: {
                    id: null,
                    name: '',
                },
                searchIndexer: {
                    id: null,
                    name: '',
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

            const vm = this;
            // @TODO: we need to move to real forms instead of this
            if (this.useFormtowizard) {
                vm.myform = new formtowizard({ // eslint-disable-line new-cap, no-undef
                    formid: 'addShowForm',
                    revealfx: ['slide', 500],
                    oninit() {
                        vm.updateSampleText();
                        if ($('input:hidden[name=whichSeries]').length !== 0 && $('#fullShowPath').length !== 0) {
                            goToStep(3);
                        }
                    }
                });

                $(document.body).on('change', 'select[name="quality_preset"]', () => {
                    setTimeout(() => vm.myform.loadsection(2), 100);
                });

                $('#anime').change(() => {
                    vm.updateSampleText();
                    setTimeout(() => vm.myform.loadsection(2), 100);
                });
            }

            this.$watch('selectedRootDir', this.updateSampleText);
            this.$watch('whichSeries', this.updateSampleText);
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
                    return whichSeries.split('|')[2];
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
            submitForm() {
                // @TODO: When switching to Vue - Don't forget about that generateBlackWhiteList...
                /*
                // If they haven't picked a show don't let them submit
                if (!$('input:radio[name="whichSeries"]:checked').val() && $('input:hidden[name="whichSeries"]').val().length === 0) {
                    alert('You must choose a show to continue'); // eslint-disable-line no-alert
                    return false;
                }
                */
                generateBlackWhiteList(); // eslint-disable-line no-undef
                // The submit is handled by Vue
                // $('#addShowForm').submit();
                return window.vueSubmitForm('addShowForm');
            },
            submitFormSkip() {
                this.skipShow = '1';
                return window.vueSubmitForm('addShowForm');
            },
            rootDirsUpdated(rootDirs) {
                this.selectedRootDir = rootDirs.length === 0 ? '' : rootDirs.find(rd => rd.selected).path;
            },
            searchIndexers() {
                let { searchRequestXhr, nameToSearch, providedInfo, indexerTimeout, language } = this;

                if (nameToSearch.length === 0) {
                    return;
                }

                if (searchRequestXhr) {
                    searchRequestXhr.abort();
                }

                this.whichSeries = '';

                const searchingFor = '<b>' + nameToSearch + '</b> on ' + $('#providedIndexer option:selected').text() + ' in ' + language;
                this.searchRequestText = '<img id="searchingAnim" src="images/loading32' + MEDUSA.config.themeSpinner + '.gif" height="32" width="32" /> searching ' + searchingFor + '...';

                searchRequestXhr = $.ajax({
                    url: 'addShows/searchIndexersForShowName',
                    data: {
                        search_term: nameToSearch, // eslint-disable-line camelcase
                        lang: language,
                        indexer: providedInfo.indexerId
                    },
                    timeout: indexerTimeout * 1000,
                    dataType: 'json',
                    error() {
                        this.searchRequestText = 'search timed out, try again or try another indexer';
                    }
                }).done(data => {
                    this.searchRequestText = '';

                    const results = data.results
                        .map(result => {
                            return {
                                indexerName: result[0],
                                indexerId: result[1],
                                indexerShowUrl: result[2],
                                seriesId: result[3],
                                seriesName: result[4],
                                premiereDate: result[5],
                                network: result[6]
                            };
                        });

                    this.searchResults = {
                        language: data.langid,
                        results
                    };

                    if (results.length !== 0) {
                        // Select the first result
                        this.whichSeries = [results[0].indexerId, results[0].seriesId, results[0].seriesName].join('|');
                    }

                    if (this.useFormtowizard) {
                        this.$nextTick(() => {
                            this.myform.loadsection(0); // eslint-disable-line no-use-before-define
                        });
                    }
                });
            },
            debutText(result) {
                if (result.premiereDate === null) return '';
                const startDate = new Date(result.premiereDate);
                const today = new Date();
                const prefix = startDate > today ? 'will debut' : 'started';
                return ' (' + prefix + ' on ' + result.premiereDate + ' on ' + result.network + ')';
            },
            updateSampleText() {
                // Currently requires jQuery
                if ($ === undefined || !this.mounted) return;
                $.updateBlackWhiteList(this.showName);
            }
        }
    });
};
</script>
</%block>
<%block name="content">
<h1 class="header">{{header}}</h1>
<div class="newShowPortal">
    <div id="config-components">
        <ul><li><app-link href="#core-component-group1">Add New Show</app-link></li></ul>
        <div id="core-component-group1" class="tab-pane active component-group">
            <div id="displayText">Adding show <b v-html="showName"></b> into <b v-html="showPath"></b></div>
            <br>
            <form id="addShowForm" method="post" action="addShows/addNewShow" redirect="/home" accept-charset="utf-8">
                <fieldset class="sectionwrap">
                    <legend class="legendStep">Find a show on selected indexer(s)</legend>
                    <div class="stepDiv">
                        % if use_provided_info:
                            Show retrieved from existing metadata: <app-link :href="indexers[providedInfo.indexerId].showUrl + providedInfo.seriesId">{{ providedInfo.indexer }}</app-link>
                            <input type="hidden" id="indexer_lang" name="indexer_lang" value="en" />
                            <input type="hidden" id="whichSeries" name="whichSeries" :value="providedInfo.seriesId" />
                            <input type="hidden" id="providedIndexer" name="providedIndexer" :value="providedInfo.indexerId" />
                            <input type="hidden" id="providedName" :value="providedInfo.indexer" />
                        % else:
                            <input type="text" v-model.trim="nameToSearch" ref="nameToSearch" @keyup.enter="searchIndexers" class="form-control form-control-inline input-sm input350"/>
                            &nbsp;&nbsp;
                            <language-select @update-language="language = $event" name="indexer_lang" id="indexerLangSelect" :language="language" :available="validLanguages.join(',')" class="form-control form-control-inline input-sm"></language-select>
                            <b>*</b>
                            &nbsp;
                            <select name="providedIndexer" id="providedIndexer" v-model="indexerId" class="form-control form-control-inline input-sm">
                                <option :value.number="0">All Indexers</option>
                                <option v-for="(indexer, indexerId) in indexers" :value.number="indexerId">{{indexer.name}}</option>
                            </select>
                            &nbsp;
                            <input class="btn-medusa btn-inline" type="button" id="searchName" value="Search" @click="searchIndexers" />
                            <br><br>
                            <b>*</b> This will only affect the language of the retrieved metadata file contents and episode filenames.<br>
                            This <b>DOES NOT</b> allow Medusa to download non-english TV episodes!<br><br>

                            ## NEW STYLE - needs styling
                            <div v-if="searchRequestText.length !== 0" v-html="searchRequestText"></div>
                            <div v-else style="height: 100%;">
                                <legend class="legendStep">Search Results:</legend>
                                <table>
                                    <thead>
                                        <tr>
                                            <td></td>
                                            <td>Show Name</td>
                                            <td>Premiere</td>
                                            <td>Indexer</td>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <tr v-if="searchResults.results.length === 0">
                                            <td colspan="4">
                                                <b>No results found, try a different search.</b>
                                            </td>
                                        </tr>
                                        <tr v-else v-for="result in searchResults.results" @click="whichSeries = [result.indexerId, result.seriesId, result.seriesName].join('|')">
                                            <td style="text-align: center; vertical-align: middle;">
                                                ## FIXME: Do we still need this value replace? .replace(/"/g, '')
                                                <input v-model="whichSeries" type="radio" :value="[result.indexerId, result.seriesId, result.seriesName].join('|')" id="whichSeries" name="whichSeries" />
                                            </td>
                                            <td>
                                                ## For now only add the language id to the tvdb url, as the others might have different routes.
                                                <app-link v-if="searchResults.language && searchResults.language !== '' && result.indexerId === 1" :href="result.indexerShowUrl + result.seriesId + '&lid=' + searchResults.language">
                                                    <b>{{ result.seriesName }}</b>
                                                </app-link>
                                                <app-link v-else :href="result.indexerShowUrl + result.seriesId">
                                                    <b>{{ result.seriesName }}</b>
                                                </app-link>
                                            </td>
                                            <td v-if="result.premiereDate !== null">{{ result.premiereDate }} on {{ result.network }}</td>
                                            <td>{{ result.indexerName || ''}}</td>
                                        </tr>
                                    </tbody>
                                </table>
                            </div>
                            ## // <END> NEW STYLE

                            ## OLD STYLE - works
                            <div id="searchResults" style="height: 100%;">
                                <span v-if="searchRequestText.length !== 0" v-html="searchRequestText"></span>
                                <fieldset v-else>
                                    <legend class="legendStep">Search Results:</legend>
                                    <b v-if="searchResults.results.length === 0">No results found, try a different search.</b>
                                    <div v-else v-for="result in searchResults.results">
                                        ## FIXME: Do we still need this value replace? .replace(/"/g, '')
                                        <input v-model="whichSeries" type="radio" :value="[result.indexerId, result.seriesId, result.seriesName].join('|')" id="whichSeries" name="whichSeries" />
                                        ## For now only add the language id to the tvdb url, as the others might have different routes.
                                        <app-link v-if="searchResults.language && searchResults.language !== '' && result.indexerId === 1" :href="result.indexerShowUrl + result.seriesId + '&lid=' + searchResults.language">
                                            <b>{{ result.seriesName }}</b>
                                        </app-link>
                                        <app-link v-else :href="result.indexerShowUrl + result.seriesId">
                                            <b>{{ result.seriesName }}</b>
                                        </app-link>

                                        <span v-if="result.premiereDate !== null" v-html="debutText(result)"></span>
                                        <span v-if="result.indexerName !== null"> [{{result.indexerName}}]</span>
                                    </div>
                                </fieldset>
                            </div>
                            ## // <END> OLD STYLE
                        % endif
                    </div>
                </fieldset>
                <fieldset class="sectionwrap">
                    <legend class="legendStep">Pick the parent folder</legend>
                    <div class="stepDiv">
                        % if provided_show_dir:
                            Pre-chosen Destination Folder: <b>{{providedInfo.seriesDir}}</b> <br>
                            <input type="hidden" id="fullShowPath" name="fullShowPath" :value="providedInfo.seriesDir" /><br>
                        % else:
                            <root-dirs @update:root-dirs="rootDirsUpdated"></root-dirs>
                        % endif
                    </div>
                </fieldset>
                <fieldset class="sectionwrap">
                    <legend class="legendStep">Customize options</legend>
                    <div class="stepDiv">
                        <%include file="/inc_addShowOptions.mako"/>
                    </div>
                </fieldset>
                % for curNextDir in other_shows:
                <input type="hidden" name="other_shows" value="${curNextDir}" />
                % endfor
                <input type="hidden" name="skipShow" id="skipShow" :value="skipShow" />
            </form>
            <br>
            <div style="width: 100%; text-align: center;">
                <input @click.prevent="submitForm" id="addShowButton" class="btn-medusa" type="button" value="Add Show" :disabled="addButtonDisabled" />
                % if provided_show_dir:
                <input @click.prevent="submitFormSkip" class="btn-medusa" type="button" id="skipShowButton" value="Skip Show" />
                % endif
            </div>
        </div>
    </div>
</div>
</%block>
